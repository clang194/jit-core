const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");

pub const RunError = error{
    UnknownInstruction,
    Unpredictable,
    Full,
    MissingRead,
    MissingWrite,
};

pub const ShiftResult = struct {
    word: u32,
    carry: bool,
};

pub const AddResult = struct {
    word: u32,
    carry: bool,
    overflow: bool,
};

pub const ThumbWord = struct {
    word: u32,
    size: u8,
};

pub fn readThumbWord(hooks: arm_state.HostHooks, pc: u32) RunError!ThumbWord {
    if (hooks.read32 == null) {
        return error.MissingRead;
    }

    const first_address = pc & 0xfffffffc;
    var first = hooks.read32.?(first_address);
    if ((pc & 2) != 0) {
        first >>= 16;
    }

    const word = @intCast(u16, first & 0xffff);
    if ((word & 0xf800) <= 0xe800) {
        return ThumbWord{ .word = word, .size = 2 };
    }

    const second_pc = pc + 2;
    var second = hooks.read32.?(second_pc & 0xfffffffc);
    if ((second_pc & 2) != 0) {
        second >>= 16;
    }

    return ThumbWord{
        .word = @as(u32, word) | ((second & 0xffff) << 16),
        .size = 4,
    };
}

pub fn isStop(word: u16) bool {
    return (word & 0xff00) == 0xde00;
}

pub fn branchTarget(word: u16, pc: u32) ?u32 {
    if ((word & 0xf800) != 0xe000) {
        return null;
    }
    const imm = @as(u32, word & 0x07ff) << 1;
    const offset = bits.signExtend32(imm, 12);
    return @intCast(u32, @intCast(i32, pc + 4) + offset);
}

pub fn branchLinkTarget(word: u32, pc: u32) ?u32 {
    const first = @intCast(u16, word & 0xffff);
    const second = @intCast(u16, (word >> 16) & 0xffff);
    if ((first & 0xf800) != 0xf000 or (second & 0xf800) != 0xf800) {
        return null;
    }
    return @bitCast(u32, @intCast(i32, pc + 4) + thumb32Offset(word));
}

pub fn branchLinkExchangeTarget(word: u32, pc: u32) RunError!?u32 {
    const first = @intCast(u16, word & 0xffff);
    const second = @intCast(u16, (word >> 16) & 0xffff);
    if ((first & 0xf800) != 0xf000 or (second & 0xf800) != 0xe800) {
        return null;
    }
    if ((second & 1) != 0) {
        return error.Unpredictable;
    }
    return @bitCast(u32, @intCast(i32, alignDown4(pc + 4)) + thumb32Offset(word));
}

pub fn buildThumbTrace(word: u16, tape: *trace.Tape) RunError!void {
    return buildThumbTraceAt(word, 0, tape);
}

pub fn buildThumbPacketTraceAt(packet: ThumbWord, pc: u32, tape: *trace.Tape) RunError!void {
    if (packet.size == 2) {
        return buildThumbTraceAt(@intCast(u16, packet.word & 0xffff), pc, tape);
    }
    if (packet.size == 4) {
        return buildThumb32TraceAt(packet.word, pc, tape);
    }
    return error.UnknownInstruction;
}

pub fn buildThumb32TraceAt(word: u32, pc: u32, tape: *trace.Tape) RunError!void {
    if (branchLinkTarget(word, pc)) |target| {
        const link = try tape.literalReg(.lr);
        _ = try tape.storeReg(link, try tape.literalWord((pc + 4) | 1));
        _ = try tape.jump(try tape.literalWord(target));
        return;
    }

    if (try branchLinkExchangeTarget(word, pc)) |target| {
        const link = try tape.literalReg(.lr);
        _ = try tape.storeReg(link, try tape.literalWord((pc + 4) | 1));
        _ = try tape.loadPc(try tape.literalWord(target));
        return;
    }

    return error.UnknownInstruction;
}

pub fn buildThumbTraceAt(word: u16, pc: u32, tape: *trace.Tape) RunError!void {
    if (isStop(word)) {
        return;
    }

    if ((word & 0xff00) == 0xdf00) {
        _ = try tape.callSupervisor(@intCast(u32, word & 0xff));
        return;
    }

    if ((word & 0xf800) == 0x0000) {
        const amount = @intCast(u8, (word >> 6) & 0x1f);
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const read = try tape.loadReg(source);
        const amount_value = try tape.literalByte(amount);
        const result = try tape.shiftLeft(read, amount_value, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return;
    }

    if ((word & 0xf800) == 0x0800) {
        var amount = @intCast(u8, (word >> 6) & 0x1f);
        if (amount == 0) {
            amount = 32;
        }
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const read = try tape.loadReg(source);
        const amount_value = try tape.literalByte(amount);
        const result = try tape.shiftRight(read, amount_value, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return;
    }

    if ((word & 0xf800) == 0x1000) {
        var amount = @intCast(u8, (word >> 6) & 0x1f);
        if (amount == 0) {
            amount = 32;
        }
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const read = try tape.loadReg(source);
        const amount_value = try tape.literalByte(amount);
        const result = try tape.shiftArithmeticRight(read, amount_value, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return;
    }

    if ((word & 0xfe00) == 0x1800) {
        const addend_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.literalBit(false);
        const base = try tape.loadReg(base_reg);
        const addend = try tape.loadReg(addend_reg);
        const result = try tape.addCarrying(base, addend, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return;
    }

    if ((word & 0xfe00) == 0x1a00) {
        const subtrahend_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.literalBit(true);
        const base = try tape.loadReg(base_reg);
        const subtrahend = try tape.loadReg(subtrahend_reg);
        const result = try tape.subCarrying(base, subtrahend, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return;
    }

    if ((word & 0xfe00) == 0x1c00) {
        const amount = try tape.literalWord(@intCast(u32, (word >> 6) & 7));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.literalBit(false);
        const base = try tape.loadReg(base_reg);
        const result = try tape.addCarrying(base, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return;
    }

    if ((word & 0xfe00) == 0x1e00) {
        const amount = try tape.literalWord(@intCast(u32, (word >> 6) & 7));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.literalBit(true);
        const base = try tape.loadReg(base_reg);
        const result = try tape.subCarrying(base, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return;
    }

    if ((word & 0xf800) == 0x2000) {
        const result = try tape.literalWord(@intCast(u32, word & 0xff));
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return;
    }

    if ((word & 0xf800) == 0x2800) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 8));
        const amount = try tape.literalWord(@intCast(u32, word & 0xff));
        const carry_in = try tape.literalBit(true);
        const source = try tape.loadReg(source_reg);
        const result = try tape.subCarrying(source, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return;
    }

    if ((word & 0xf800) == 0x3000) {
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        const amount = try tape.literalWord(@intCast(u32, word & 0xff));
        const carry_in = try tape.literalBit(false);
        const source = try tape.loadReg(dest);
        const result = try tape.addCarrying(source, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return;
    }

    if ((word & 0xf800) == 0x3800) {
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        const amount = try tape.literalWord(@intCast(u32, word & 0xff));
        const carry_in = try tape.literalBit(true);
        const source = try tape.loadReg(dest);
        const result = try tape.subCarrying(source, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return;
    }

    if ((word & 0xffc0) == 0x4000) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const read = try tape.loadReg(dest);
        const mask = try tape.loadReg(source);
        const result = try tape.bitwiseAnd(read, mask);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return;
    }

    if ((word & 0xffc0) == 0x4040) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const read = try tape.loadReg(dest);
        const mask = try tape.loadReg(source);
        const result = try tape.bitwiseXor(read, mask);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return;
    }

    if ((word & 0xffc0) == 0x4080) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const amount_word = try tape.loadReg(source);
        const amount = try tape.lowByte(amount_word);
        const read = try tape.loadReg(dest);
        const result = try tape.shiftLeft(read, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return;
    }

    if ((word & 0xffc0) == 0x40c0) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const amount_word = try tape.loadReg(source);
        const amount = try tape.lowByte(amount_word);
        const read = try tape.loadReg(dest);
        const result = try tape.shiftRight(read, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return;
    }

    if ((word & 0xffc0) == 0x4100) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const amount_word = try tape.loadReg(source);
        const amount = try tape.lowByte(amount_word);
        const read = try tape.loadReg(dest);
        const result = try tape.shiftArithmeticRight(read, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return;
    }

    if ((word & 0xffc0) == 0x4140) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const read = try tape.loadReg(dest);
        const addend = try tape.loadReg(source);
        const result = try tape.addCarrying(read, addend, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return;
    }

    if ((word & 0xffc0) == 0x4180) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const read = try tape.loadReg(dest);
        const subtrahend = try tape.loadReg(source);
        const result = try tape.subCarrying(read, subtrahend, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return;
    }

    if ((word & 0xffc0) == 0x41c0) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const amount_word = try tape.loadReg(source);
        const amount = try tape.lowByte(amount_word);
        const read = try tape.loadReg(dest);
        const result = try tape.rotateRight(read, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return;
    }

    if ((word & 0xffc0) == 0x4200) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const read = try tape.loadReg(dest);
        const mask = try tape.loadReg(source);
        const result = try tape.bitwiseAnd(read, mask);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return;
    }

    if ((word & 0xffc0) == 0x4240) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const zero = try tape.literalWord(0);
        const carry_in = try tape.literalBit(true);
        const source = try tape.loadReg(source_reg);
        const result = try tape.subCarrying(zero, source, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return;
    }

    if ((word & 0xffc0) == 0x4280) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.literalBit(true);
        const left = try tape.loadReg(dest);
        const right = try tape.loadReg(source_reg);
        const result = try tape.subCarrying(left, right, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return;
    }

    if ((word & 0xffc0) == 0x42c0) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.literalBit(false);
        const left = try tape.loadReg(dest);
        const right = try tape.loadReg(source_reg);
        const result = try tape.addCarrying(left, right, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return;
    }

    if ((word & 0xffc0) == 0x4300) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const read = try tape.loadReg(dest);
        const mask = try tape.loadReg(source);
        const result = try tape.bitwiseOr(read, mask);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return;
    }

    if ((word & 0xffc0) == 0x4380) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const read = try tape.loadReg(dest);
        const mask_read = try tape.loadReg(source);
        const mask = try tape.bitwiseNot(mask_read);
        const result = try tape.bitwiseAnd(read, mask);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return;
    }

    if ((word & 0xffc0) == 0x43c0) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const read = try tape.loadReg(source);
        const result = try tape.bitwiseNot(read);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return;
    }

    if ((word & 0xff00) == 0x4400) {
        const dest_reg = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const addend_reg = arm_state.reg4(word >> 3);
        if (dest_reg == .pc and addend_reg == .pc) {
            return error.Unpredictable;
        }
        const dest = try tape.literalReg(dest_reg);
        const left = try traceOperand(tape, dest_reg, pc);
        const right = try traceOperand(tape, addend_reg, pc);
        const carry_in = try tape.literalBit(false);
        const result = try tape.addCarrying(left, right, carry_in);
        _ = try tape.storeReg(dest, result);
        return;
    }

    if ((word & 0xff00) == 0x4500) {
        const left_reg = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const right_reg = arm_state.reg4(word >> 3);
        if ((@enumToInt(left_reg) < 8 and @enumToInt(right_reg) < 8) or left_reg == .pc or right_reg == .pc) {
            return error.Unpredictable;
        }
        const left = try traceOperand(tape, left_reg, pc);
        const right = try traceOperand(tape, right_reg, pc);
        const carry_in = try tape.literalBit(true);
        const result = try tape.subCarrying(left, right, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return;
    }

    if ((word & 0xff00) == 0x4600) {
        const dest_reg = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const source_reg = arm_state.reg4(word >> 3);
        const dest = try tape.literalReg(dest_reg);
        const source = try traceOperand(tape, source_reg, pc);
        if (dest_reg == .pc) {
            const mask = try tape.literalWord(0xfffffffe);
            _ = try tape.storeReg(dest, try tape.bitwiseAnd(source, mask));
        } else {
            _ = try tape.storeReg(dest, source);
        }
        return;
    }

    if ((word & 0xff87) == 0x4700) {
        const source = try traceOperand(tape, arm_state.reg4(word >> 3), pc);
        _ = try tape.loadPc(source);
        return;
    }

    if ((word & 0xff87) == 0x4780) {
        const link = try tape.literalReg(.lr);
        _ = try tape.storeReg(link, try tape.literalWord((pc + 2) | 1));
        const source = try traceOperand(tape, arm_state.reg4(word >> 3), pc);
        _ = try tape.loadPc(source);
        return;
    }

    if ((word & 0xf800) == 0x4800) {
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        const address = try tape.literalWord(alignDown4(pc + 4) + (@as(u32, word & 0xff) << 2));
        const data = try tape.readWord(address);
        _ = try tape.storeReg(dest, data);
        return;
    }

    if ((word & 0xfe00) == 0x5000) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const data_reg = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.loadReg(data_reg);
        _ = try tape.writeWord(address, data);
        return;
    }

    if ((word & 0xfe00) == 0x5200) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const data_reg = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.lowHalf(try tape.loadReg(data_reg));
        _ = try tape.writeHalf(address, data);
        return;
    }

    if ((word & 0xfe00) == 0x5400) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const data_reg = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.lowByte(try tape.loadReg(data_reg));
        _ = try tape.writeByte(address, data);
        return;
    }

    if ((word & 0xfe00) == 0x5600) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.readByte(address);
        _ = try tape.storeReg(dest, try tape.signExtendByte(data));
        return;
    }

    if ((word & 0xfe00) == 0x5800) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        _ = try tape.storeReg(dest, try tape.readWord(address));
        return;
    }

    if ((word & 0xfe00) == 0x5a00) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.readHalf(address);
        _ = try tape.storeReg(dest, try tape.zeroExtendHalf(data));
        return;
    }

    if ((word & 0xfe00) == 0x5c00) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.readByte(address);
        _ = try tape.storeReg(dest, try tape.zeroExtendByte(data));
        return;
    }

    if ((word & 0xfe00) == 0x5e00) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.readHalf(address);
        _ = try tape.storeReg(dest, try tape.signExtendHalf(data));
        return;
    }

    if ((word & 0xf800) == 0x6000) {
        const amount = try tape.literalWord(@as(u32, (word >> 6) & 0x1f) << 2);
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const data_reg = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.loadReg(data_reg);
        _ = try tape.writeWord(address, data);
        return;
    }

    if ((word & 0xf800) == 0x6800) {
        const amount = try tape.literalWord(@as(u32, (word >> 6) & 0x1f) << 2);
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.readWord(address);
        _ = try tape.storeReg(dest, data);
        return;
    }

    if ((word & 0xf800) == 0x7000) {
        const amount = try tape.literalWord(@as(u32, (word >> 6) & 0x1f));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const data_reg = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.lowByte(try tape.loadReg(data_reg));
        _ = try tape.writeByte(address, data);
        return;
    }

    if ((word & 0xf800) == 0x7800) {
        const amount = try tape.literalWord(@as(u32, (word >> 6) & 0x1f));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.readByte(address);
        _ = try tape.storeReg(dest, try tape.zeroExtendByte(data));
        return;
    }

    if ((word & 0xf800) == 0x8000) {
        const amount = try tape.literalWord(@as(u32, (word >> 6) & 0x1f) << 1);
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const data_reg = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.lowHalf(try tape.loadReg(data_reg));
        _ = try tape.writeHalf(address, data);
        return;
    }

    if ((word & 0xf800) == 0x8800) {
        const amount = try tape.literalWord(@as(u32, (word >> 6) & 0x1f) << 1);
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.readHalf(address);
        _ = try tape.storeReg(dest, try tape.zeroExtendHalf(data));
        return;
    }

    if ((word & 0xf800) == 0x9000) {
        const amount = try tape.literalWord(@as(u32, word & 0xff) << 2);
        const base_reg = try tape.literalReg(.sp);
        const data_reg = try tape.literalReg(arm_state.lowReg(word >> 8));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.loadReg(data_reg);
        _ = try tape.writeWord(address, data);
        return;
    }

    if ((word & 0xf800) == 0x9800) {
        const amount = try tape.literalWord(@as(u32, word & 0xff) << 2);
        const base_reg = try tape.literalReg(.sp);
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        _ = try tape.storeReg(dest, try tape.readWord(address));
        return;
    }

    if ((word & 0xf800) == 0xa000) {
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        const base = try tape.literalWord(alignDown4(pc + 4));
        const amount = try tape.literalWord(@as(u32, word & 0xff) << 2);
        _ = try tape.storeReg(dest, try tape.wordAdd(base, amount));
        return;
    }

    if ((word & 0xf800) == 0xa800) {
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        const base_reg = try tape.literalReg(.sp);
        const base = try tape.loadReg(base_reg);
        const amount = try tape.literalWord(@as(u32, word & 0xff) << 2);
        const carry_in = try tape.literalBit(false);
        _ = try tape.storeReg(dest, try tape.addCarrying(base, amount, carry_in));
        return;
    }

    if ((word & 0xff80) == 0xb000) {
        const dest = try tape.literalReg(.sp);
        const base = try tape.loadReg(dest);
        const amount = try tape.literalWord(@as(u32, word & 0x7f) << 2);
        const carry_in = try tape.literalBit(false);
        _ = try tape.storeReg(dest, try tape.addCarrying(base, amount, carry_in));
        return;
    }

    if ((word & 0xff80) == 0xb080) {
        const dest = try tape.literalReg(.sp);
        const base = try tape.loadReg(dest);
        const amount = try tape.literalWord(@as(u32, word & 0x7f) << 2);
        const carry_in = try tape.literalBit(true);
        _ = try tape.storeReg(dest, try tape.subCarrying(base, amount, carry_in));
        return;
    }

    if ((word & 0xfe00) == 0xb400) {
        const mask = pushMask(word);
        const count = bits.countLow16(mask);
        if (count == 0) {
            return error.Unpredictable;
        }
        const sp_reg = try tape.literalReg(.sp);
        const old_sp = try tape.loadReg(sp_reg);
        const amount = try tape.literalWord(@as(u32, count) << 2);
        const carry_in = try tape.literalBit(true);
        const final_sp = try tape.subCarrying(old_sp, amount, carry_in);
        var address = final_sp;
        var index: u8 = 0;
        while (index < 16) : (index += 1) {
            if ((mask & (@as(u16, 1) << @intCast(u4, index))) != 0) {
                const reg = try tape.literalReg(@intToEnum(arm_state.ArmReg, index));
                const value = try tape.loadReg(reg);
                _ = try tape.writeWord(address, value);
                address = try tape.wordAdd(address, try tape.literalWord(4));
            }
        }
        _ = try tape.storeReg(sp_reg, final_sp);
        return;
    }

    if ((word & 0xfe00) == 0xbc00) {
        const mask = popMask(word);
        const count = bits.countLow16(mask);
        if (count == 0) {
            return error.Unpredictable;
        }
        const sp_reg = try tape.literalReg(.sp);
        var address = try tape.loadReg(sp_reg);
        var index: u8 = 0;
        while (index < 15) : (index += 1) {
            if ((mask & (@as(u16, 1) << @intCast(u4, index))) != 0) {
                const reg = try tape.literalReg(@intToEnum(arm_state.ArmReg, index));
                const data = try tape.readWord(address);
                _ = try tape.storeReg(reg, data);
                address = try tape.wordAdd(address, try tape.literalWord(4));
            }
        }
        if ((mask & (@as(u16, 1) << 15)) != 0) {
            const data = try tape.readWord(address);
            _ = try tape.loadPc(data);
            address = try tape.wordAdd(address, try tape.literalWord(4));
        }
        _ = try tape.storeReg(sp_reg, address);
        return;
    }

    if ((word & 0xfff7) == 0xb650) {
        _ = try tape.storeEndian(try tape.literalBit((word & 8) != 0));
        return;
    }

    if ((word & 0xf800) == 0xc000) {
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 8));
        var address = try tape.loadReg(base_reg);
        const mask = @intCast(u8, word & 0xff);
        var index: u8 = 0;
        while (index < 8) : (index += 1) {
            if ((mask & (@as(u8, 1) << @intCast(u3, index))) != 0) {
                const data_reg = try tape.literalReg(@intToEnum(arm_state.ArmReg, index));
                const data = try tape.loadReg(data_reg);
                _ = try tape.writeWord(address, data);
                address = try tape.wordAdd(address, try tape.literalWord(4));
            }
        }
        _ = try tape.storeReg(base_reg, address);
        return;
    }

    if ((word & 0xf800) == 0xc800) {
        const base = arm_state.lowReg(word >> 8);
        const base_reg = try tape.literalReg(base);
        var address = try tape.loadReg(base_reg);
        const mask = @intCast(u8, word & 0xff);
        var index: u8 = 0;
        while (index < 8) : (index += 1) {
            if ((mask & (@as(u8, 1) << @intCast(u3, index))) != 0) {
                const dest = try tape.literalReg(@intToEnum(arm_state.ArmReg, index));
                const data = try tape.readWord(address);
                _ = try tape.storeReg(dest, data);
                address = try tape.wordAdd(address, try tape.literalWord(4));
            }
        }
        if ((mask & (@as(u8, 1) << @intCast(u3, @enumToInt(base)))) == 0) {
            _ = try tape.storeReg(base_reg, address);
        }
        return;
    }

    if ((word & 0xffc0) == 0xb200) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        const half = try tape.lowHalf(source);
        _ = try tape.storeReg(dest, try tape.signExtendHalf(half));
        return;
    }

    if ((word & 0xffc0) == 0xb240) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        const byte = try tape.lowByte(source);
        _ = try tape.storeReg(dest, try tape.signExtendByte(byte));
        return;
    }

    if ((word & 0xffc0) == 0xb280) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        const half = try tape.lowHalf(source);
        _ = try tape.storeReg(dest, try tape.zeroExtendHalf(half));
        return;
    }

    if ((word & 0xffc0) == 0xb2c0) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        const byte = try tape.lowByte(source);
        _ = try tape.storeReg(dest, try tape.zeroExtendByte(byte));
        return;
    }

    if ((word & 0xffc0) == 0xba00) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        _ = try tape.storeReg(dest, try tape.byteReverseWord(source));
        return;
    }

    if ((word & 0xffc0) == 0xba40) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        const low = try tape.byteReverseHalf(try tape.lowHalf(source));
        const shift = try tape.literalByte(16);
        const carry_in = try tape.literalBit(false);
        const high_shifted = try tape.shiftRight(source, shift, carry_in);
        const high = try tape.byteReverseHalf(try tape.lowHalf(high_shifted));
        const high_word = try tape.zeroExtendHalf(high);
        const low_word = try tape.zeroExtendHalf(low);
        const moved_high = try tape.shiftLeft(high_word, shift, carry_in);
        _ = try tape.storeReg(dest, try tape.bitwiseOr(moved_high, low_word));
        return;
    }

    if ((word & 0xffc0) == 0xbac0) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        const half = try tape.byteReverseHalf(try tape.lowHalf(source));
        _ = try tape.storeReg(dest, try tape.signExtendHalf(half));
        return;
    }

    if ((word & 0xf000) == 0xd000 and (word & 0x0f00) < 0x0e00) {
        const cond = try tape.literalByte(@intCast(u8, (word >> 8) & 0xf));
        const offset = bits.signExtend32(@as(u32, word & 0xff) << 1, 9);
        const taken = try tape.literalWord(@intCast(u32, @intCast(i32, pc + 4) + offset));
        const skipped = try tape.literalWord(pc + 2);
        _ = try tape.branchIf(cond, taken, skipped);
        return;
    }

    if ((word & 0xf800) == 0xe000) {
        const target = try tape.literalWord(branchTarget(word, pc).?);
        _ = try tape.jump(target);
        return;
    }

    return error.UnknownInstruction;
}

pub fn runThumb(word: u16, state: *arm_state.MachineState) RunError!void {
    return runThumbWithHooks(word, state, arm_state.HostHooks.empty());
}

pub fn runThumbPacketWithHooks(packet: ThumbWord, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!void {
    if (packet.size == 2) {
        return runThumbWithHooks(@intCast(u16, packet.word & 0xffff), state, hooks);
    }
    if (packet.size == 4) {
        return runThumb32WithHooks(packet.word, state, hooks);
    }
    return error.UnknownInstruction;
}

pub fn runThumb32WithHooks(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!void {
    _ = hooks;
    const pc = state.read(.pc);
    if (branchLinkTarget(word, pc)) |target| {
        state.write(.lr, (pc + 4) | 1);
        state.write(.pc, target);
        return;
    }
    if (try branchLinkExchangeTarget(word, pc)) |target| {
        state.write(.lr, (pc + 4) | 1);
        state.setThumb(false);
        state.write(.pc, target);
        return;
    }
    return error.UnknownInstruction;
}

pub fn runThumbWithHooks(word: u16, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!void {
    if (isStop(word)) {
        return;
    }

    if ((word & 0xff00) == 0xdf00) {
        if (hooks.supervisor) |callback| {
            callback(@intCast(u32, word & 0xff), state);
            return;
        }
        if (hooks.fallback) |callback| {
            callback(state.read(.pc), state);
            return;
        }
        return error.UnknownInstruction;
    }

    if ((word & 0xf800) == 0x0000) {
        const amount = @intCast(u8, (word >> 6) & 0x1f);
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = logicalLeft(state.read(source), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return;
    }

    if ((word & 0xf800) == 0x0800) {
        var amount = @intCast(u8, (word >> 6) & 0x1f);
        if (amount == 0) {
            amount = 32;
        }
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = logicalRight(state.read(source), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return;
    }

    if ((word & 0xf800) == 0x1000) {
        var amount = @intCast(u8, (word >> 6) & 0x1f);
        if (amount == 0) {
            amount = 32;
        }
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = arithmeticRight(state.read(source), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return;
    }

    if ((word & 0xfe00) == 0x1800) {
        const addend = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = addWithCarry(state.read(base), state.read(addend), false);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xfe00) == 0x1a00) {
        const subtrahend = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = subWithCarry(state.read(base), state.read(subtrahend), true);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xfe00) == 0x1c00) {
        const amount = @intCast(u32, (word >> 6) & 7);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = addWithCarry(state.read(base), amount, false);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xfe00) == 0x1e00) {
        const amount = @intCast(u32, (word >> 6) & 7);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = subWithCarry(state.read(base), amount, true);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xf800) == 0x2000) {
        const dest = arm_state.lowReg(word >> 8);
        const result = @intCast(u32, word & 0xff);
        state.write(dest, result);
        updateNz(state, result);
        return;
    }

    if ((word & 0xf800) == 0x2800) {
        const source = arm_state.lowReg(word >> 8);
        const amount = @intCast(u32, word & 0xff);
        const result = subWithCarry(state.read(source), amount, true);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xf800) == 0x3000) {
        const dest = arm_state.lowReg(word >> 8);
        const amount = @intCast(u32, word & 0xff);
        const result = addWithCarry(state.read(dest), amount, false);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xf800) == 0x3800) {
        const dest = arm_state.lowReg(word >> 8);
        const amount = @intCast(u32, word & 0xff);
        const result = subWithCarry(state.read(dest), amount, true);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xffc0) == 0x4000) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) & state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return;
    }

    if ((word & 0xffc0) == 0x4040) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) ^ state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return;
    }

    if ((word & 0xffc0) == 0x4080) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const amount = bits.lowByte(state.read(source));
        const result = logicalLeft(state.read(dest), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return;
    }

    if ((word & 0xffc0) == 0x40c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const amount = bits.lowByte(state.read(source));
        const result = logicalRight(state.read(dest), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return;
    }

    if ((word & 0xffc0) == 0x4100) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const amount = bits.lowByte(state.read(source));
        const result = arithmeticRight(state.read(dest), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return;
    }

    if ((word & 0xffc0) == 0x4140) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = addWithCarry(state.read(dest), state.read(source), state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xffc0) == 0x4180) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = subWithCarry(state.read(dest), state.read(source), state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xffc0) == 0x41c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const amount = bits.lowByte(state.read(source));
        const result = rotateRight(state.read(dest), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return;
    }

    if ((word & 0xffc0) == 0x4200) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        updateNz(state, state.read(dest) & state.read(source));
        return;
    }

    if ((word & 0xffc0) == 0x4240) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = subWithCarry(0, state.read(source), true);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xffc0) == 0x4280) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = subWithCarry(state.read(dest), state.read(source), true);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xffc0) == 0x42c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = addWithCarry(state.read(dest), state.read(source), false);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xffc0) == 0x4300) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) | state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return;
    }

    if ((word & 0xffc0) == 0x4380) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) & ~state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return;
    }

    if ((word & 0xffc0) == 0x43c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = ~state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return;
    }

    if ((word & 0xff00) == 0x4400) {
        const dest = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const addend = arm_state.reg4(word >> 3);
        if (dest == .pc and addend == .pc) {
            return error.Unpredictable;
        }
        const pc = state.read(.pc);
        const left = readOperand(state, dest, pc);
        const right = readOperand(state, addend, pc);
        const result = addWithCarry(left, right, false);
        state.write(dest, result.word);
        return;
    }

    if ((word & 0xff00) == 0x4500) {
        const left_reg = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const right_reg = arm_state.reg4(word >> 3);
        if ((@enumToInt(left_reg) < 8 and @enumToInt(right_reg) < 8) or left_reg == .pc or right_reg == .pc) {
            return error.Unpredictable;
        }
        const result = subWithCarry(state.read(left_reg), state.read(right_reg), true);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xff00) == 0x4600) {
        const dest = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const source = arm_state.reg4(word >> 3);
        const pc = state.read(.pc);
        const value = readOperand(state, source, pc);
        if (dest == .pc) {
            state.write(.pc, thumbPcWrite(value));
        } else {
            state.write(dest, value);
        }
        return;
    }

    if ((word & 0xff87) == 0x4700) {
        const source = arm_state.reg4(word >> 3);
        const pc = state.read(.pc);
        loadWritePc(state, readOperand(state, source, pc));
        return;
    }

    if ((word & 0xff87) == 0x4780) {
        const source = arm_state.reg4(word >> 3);
        const pc = state.read(.pc);
        state.write(.lr, (pc + 2) | 1);
        loadWritePc(state, readOperand(state, source, pc));
        return;
    }

    if ((word & 0xf800) == 0x4800) {
        const dest = arm_state.lowReg(word >> 8);
        const pc = state.read(.pc);
        const address = alignDown4(pc + 4) + (@as(u32, word & 0xff) << 2);
        state.write(dest, try readMemory32(state, hooks, address));
        return;
    }

    if ((word & 0xfe00) == 0x5000) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const data = arm_state.lowReg(word);
        try writeMemory32(state, hooks, state.read(base) + state.read(source), state.read(data));
        return;
    }

    if ((word & 0xfe00) == 0x5200) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const data = arm_state.lowReg(word);
        try writeMemory16(state, hooks, state.read(base) + state.read(source), @intCast(u16, state.read(data) & 0xffff));
        return;
    }

    if ((word & 0xfe00) == 0x5400) {
        const write8 = hooks.write8 orelse return error.MissingWrite;
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const data = arm_state.lowReg(word);
        write8(state.read(base) + state.read(source), bits.lowByte(state.read(data)));
        return;
    }

    if ((word & 0xfe00) == 0x5600) {
        const read8 = hooks.read8 orelse return error.MissingRead;
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendByte(read8(state.read(base) + state.read(source))));
        return;
    }

    if ((word & 0xfe00) == 0x5800) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, try readMemory32(state, hooks, state.read(base) + state.read(source)));
        return;
    }

    if ((word & 0xfe00) == 0x5a00) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, try readMemory16(state, hooks, state.read(base) + state.read(source)));
        return;
    }

    if ((word & 0xfe00) == 0x5c00) {
        const read8 = hooks.read8 orelse return error.MissingRead;
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, read8(state.read(base) + state.read(source)));
        return;
    }

    if ((word & 0xfe00) == 0x5e00) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendHalf(try readMemory16(state, hooks, state.read(base) + state.read(source))));
        return;
    }

    if ((word & 0xf800) == 0x6000) {
        const data = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f) << 2;
        try writeMemory32(state, hooks, state.read(base) + offset, state.read(data));
        return;
    }

    if ((word & 0xf800) == 0x6800) {
        const dest = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f) << 2;
        state.write(dest, try readMemory32(state, hooks, state.read(base) + offset));
        return;
    }

    if ((word & 0xf800) == 0x7000) {
        const write8 = hooks.write8 orelse return error.MissingWrite;
        const data = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f);
        write8(state.read(base) + offset, bits.lowByte(state.read(data)));
        return;
    }

    if ((word & 0xf800) == 0x7800) {
        const read8 = hooks.read8 orelse return error.MissingRead;
        const dest = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f);
        state.write(dest, read8(state.read(base) + offset));
        return;
    }

    if ((word & 0xf800) == 0x8000) {
        const data = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f) << 1;
        try writeMemory16(state, hooks, state.read(base) + offset, @intCast(u16, state.read(data) & 0xffff));
        return;
    }

    if ((word & 0xf800) == 0x8800) {
        const dest = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f) << 1;
        state.write(dest, try readMemory16(state, hooks, state.read(base) + offset));
        return;
    }

    if ((word & 0xf800) == 0x9000) {
        const data = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        try writeMemory32(state, hooks, state.read(.sp) + offset, state.read(data));
        return;
    }

    if ((word & 0xf800) == 0x9800) {
        const dest = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        state.write(dest, try readMemory32(state, hooks, state.read(.sp) + offset));
        return;
    }

    if ((word & 0xf800) == 0xa000) {
        const dest = arm_state.lowReg(word >> 8);
        const pc = state.read(.pc);
        state.write(dest, alignDown4(pc + 4) + (@as(u32, word & 0xff) << 2));
        return;
    }

    if ((word & 0xf800) == 0xa800) {
        const dest = arm_state.lowReg(word >> 8);
        const amount = @as(u32, word & 0xff) << 2;
        const result = addWithCarry(state.read(.sp), amount, false);
        state.write(dest, result.word);
        return;
    }

    if ((word & 0xff80) == 0xb000) {
        const amount = @as(u32, word & 0x7f) << 2;
        const result = addWithCarry(state.read(.sp), amount, false);
        state.write(.sp, result.word);
        return;
    }

    if ((word & 0xff80) == 0xb080) {
        const amount = @as(u32, word & 0x7f) << 2;
        const result = subWithCarry(state.read(.sp), amount, true);
        state.write(.sp, result.word);
        return;
    }

    if ((word & 0xfe00) == 0xb400) {
        const mask = pushMask(word);
        const count = bits.countLow16(mask);
        if (count == 0) {
            return error.Unpredictable;
        }
        const final_sp = state.read(.sp) -% (@as(u32, count) << 2);
        var address = final_sp;
        var index: u8 = 0;
        while (index < 16) : (index += 1) {
            if ((mask & (@as(u16, 1) << @intCast(u4, index))) != 0) {
                try writeMemory32(state, hooks, address, state.read(@intToEnum(arm_state.ArmReg, index)));
                address +%= 4;
            }
        }
        state.write(.sp, final_sp);
        return;
    }

    if ((word & 0xfe00) == 0xbc00) {
        const mask = popMask(word);
        const count = bits.countLow16(mask);
        if (count == 0) {
            return error.Unpredictable;
        }
        var address = state.read(.sp);
        var index: u8 = 0;
        while (index < 15) : (index += 1) {
            if ((mask & (@as(u16, 1) << @intCast(u4, index))) != 0) {
                state.write(@intToEnum(arm_state.ArmReg, index), try readMemory32(state, hooks, address));
                address +%= 4;
            }
        }
        if ((mask & (@as(u16, 1) << 15)) != 0) {
            loadWritePc(state, try readMemory32(state, hooks, address));
            address +%= 4;
        }
        state.write(.sp, address);
        return;
    }

    if ((word & 0xfff7) == 0xb650) {
        state.setBigEndian((word & 8) != 0);
        return;
    }

    if ((word & 0xf800) == 0xc000) {
        const base = arm_state.lowReg(word >> 8);
        const mask = @intCast(u8, word & 0xff);
        var address = state.read(base);
        var index: u8 = 0;
        while (index < 8) : (index += 1) {
            if ((mask & (@as(u8, 1) << @intCast(u3, index))) != 0) {
                try writeMemory32(state, hooks, address, state.read(@intToEnum(arm_state.ArmReg, index)));
                address +%= 4;
            }
        }
        state.write(base, address);
        return;
    }

    if ((word & 0xf800) == 0xc800) {
        const base = arm_state.lowReg(word >> 8);
        const mask = @intCast(u8, word & 0xff);
        var address = state.read(base);
        var index: u8 = 0;
        while (index < 8) : (index += 1) {
            if ((mask & (@as(u8, 1) << @intCast(u3, index))) != 0) {
                state.write(@intToEnum(arm_state.ArmReg, index), try readMemory32(state, hooks, address));
                address +%= 4;
            }
        }
        if ((mask & (@as(u8, 1) << @intCast(u3, @enumToInt(base)))) == 0) {
            state.write(base, address);
        }
        return;
    }

    if ((word & 0xffc0) == 0xb200) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendHalf(state.read(source)));
        return;
    }

    if ((word & 0xffc0) == 0xb240) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendByte(state.read(source)));
        return;
    }

    if ((word & 0xffc0) == 0xb280) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, state.read(source) & 0xffff);
        return;
    }

    if ((word & 0xffc0) == 0xb2c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, state.read(source) & 0xff);
        return;
    }

    if ((word & 0xffc0) == 0xba00) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, byteReverseWord(state.read(source)));
        return;
    }

    if ((word & 0xffc0) == 0xba40) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, byteReverseHalfwords(state.read(source)));
        return;
    }

    if ((word & 0xffc0) == 0xbac0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendHalf(byteReverseHalf(state.read(source))));
        return;
    }

    if ((word & 0xf000) == 0xd000 and (word & 0x0f00) < 0x0e00) {
        const code = arm_state.conditionFromNibble(@intCast(u4, (word >> 8) & 0xf)).?;
        if (state.conditionHolds(code)) {
            const pc = state.read(.pc);
            const offset = bits.signExtend32(@as(u32, word & 0xff) << 1, 9);
            state.write(.pc, @intCast(u32, @intCast(i32, pc + 4) + offset));
        }
        return;
    }

    if ((word & 0xf800) == 0xe000) {
        state.write(.pc, branchTarget(word, state.read(.pc)).?);
        return;
    }

    return error.UnknownInstruction;
}

pub fn logicalLeft(value: u32, amount: u8, carry_in: bool) ShiftResult {
    if (amount == 0) {
        return ShiftResult{ .word = value, .carry = carry_in };
    }
    if (amount < 32) {
        return ShiftResult{
            .word = value << @intCast(u5, amount),
            .carry = bits.getBit32(value, @intCast(u5, 32 - amount)),
        };
    }
    if (amount == 32) {
        return ShiftResult{ .word = 0, .carry = bits.getBit32(value, 0) };
    }
    return ShiftResult{ .word = 0, .carry = false };
}

pub fn logicalRight(value: u32, amount: u8, carry_in: bool) ShiftResult {
    if (amount == 0) {
        return ShiftResult{ .word = value, .carry = carry_in };
    }
    if (amount < 32) {
        return ShiftResult{
            .word = value >> @intCast(u5, amount),
            .carry = bits.getBit32(value, @intCast(u5, amount - 1)),
        };
    }
    if (amount == 32) {
        return ShiftResult{ .word = 0, .carry = bits.getBit32(value, 31) };
    }
    return ShiftResult{ .word = 0, .carry = false };
}

pub fn arithmeticRight(value: u32, amount: u8, carry_in: bool) ShiftResult {
    if (amount == 0) {
        return ShiftResult{ .word = value, .carry = carry_in };
    }
    if (amount < 32) {
        const shift = @intCast(u5, amount);
        const fill = if (bits.topBit(value)) (~@as(u32, 0)) << @intCast(u5, 32 - amount) else @as(u32, 0);
        return ShiftResult{
            .word = (value >> shift) | fill,
            .carry = bits.getBit32(value, @intCast(u5, amount - 1)),
        };
    }
    if (bits.topBit(value)) {
        return ShiftResult{ .word = 0xffffffff, .carry = true };
    }
    return ShiftResult{ .word = 0, .carry = false };
}

pub fn rotateRight(value: u32, amount: u8, carry_in: bool) ShiftResult {
    if (amount == 0) {
        return ShiftResult{ .word = value, .carry = carry_in };
    }
    const shift = amount & 31;
    if (shift == 0) {
        return ShiftResult{ .word = value, .carry = bits.topBit(value) };
    }
    const word = (value >> @intCast(u5, shift)) | (value << @intCast(u5, 32 - shift));
    return ShiftResult{ .word = word, .carry = bits.topBit(word) };
}

pub fn addWithCarry(left: u32, right: u32, carry_in: bool) AddResult {
    const carry: u64 = if (carry_in) 1 else 0;
    const wide = @as(u64, left) + @as(u64, right) + carry;
    const result = @intCast(u32, wide & 0xffffffff);
    const overflow = ((~(left ^ right) & (left ^ result)) & 0x80000000) != 0;
    return AddResult{
        .word = result,
        .carry = wide > 0xffffffff,
        .overflow = overflow,
    };
}

pub fn subWithCarry(left: u32, right: u32, carry_in: bool) AddResult {
    return addWithCarry(left, ~right, carry_in);
}

fn pushMask(word: u16) u16 {
    var mask = word & 0xff;
    if ((word & 0x0100) != 0) {
        mask |= @as(u16, 1) << 14;
    }
    return mask;
}

fn popMask(word: u16) u16 {
    var mask = word & 0xff;
    if ((word & 0x0100) != 0) {
        mask |= @as(u16, 1) << 15;
    }
    return mask;
}

pub fn signExtendHalf(value: u32) u32 {
    return @bitCast(u32, bits.signExtend32(value, 16));
}

pub fn signExtendByte(value: u32) u32 {
    return @bitCast(u32, bits.signExtend32(value, 8));
}

pub fn byteReverseWord(value: u32) u32 {
    return ((value & 0x000000ff) << 24) |
        ((value & 0x0000ff00) << 8) |
        ((value & 0x00ff0000) >> 8) |
        ((value & 0xff000000) >> 24);
}

pub fn byteReverseHalf(value: u32) u32 {
    return ((value & 0xff) << 8) | ((value >> 8) & 0xff);
}

pub fn byteReverseHalfwords(value: u32) u32 {
    return ((value & 0x00ff00ff) << 8) | ((value & 0xff00ff00) >> 8);
}

fn readMemory16(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32) RunError!u16 {
    const read16 = hooks.read16 orelse return error.MissingRead;
    var value = read16(address);
    if (state.bigEndian()) {
        value = @intCast(u16, byteReverseHalf(value));
    }
    return value;
}

fn readMemory32(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32) RunError!u32 {
    const read32 = hooks.read32 orelse return error.MissingRead;
    var value = read32(address);
    if (state.bigEndian()) {
        value = byteReverseWord(value);
    }
    return value;
}

fn writeMemory16(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32, value: u16) RunError!void {
    const write16 = hooks.write16 orelse return error.MissingWrite;
    var data = value;
    if (state.bigEndian()) {
        data = @intCast(u16, byteReverseHalf(data));
    }
    write16(address, data);
}

fn writeMemory32(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32, value: u32) RunError!void {
    const write32 = hooks.write32 orelse return error.MissingWrite;
    var data = value;
    if (state.bigEndian()) {
        data = byteReverseWord(data);
    }
    write32(address, data);
}

fn readOperand(state: *const arm_state.MachineState, reg: arm_state.ArmReg, pc: u32) u32 {
    if (reg == .pc) {
        return pc + 4;
    }
    return state.read(reg);
}

fn traceOperand(tape: *trace.Tape, reg: arm_state.ArmReg, pc: u32) RunError!usize {
    if (reg == .pc) {
        return tape.literalWord(pc + 4);
    }
    const stored_reg = try tape.literalReg(reg);
    return tape.loadReg(stored_reg);
}

fn alignDown4(value: u32) u32 {
    return value & 0xfffffffc;
}

fn thumb32Offset(word: u32) i32 {
    const first = word & 0x07ff;
    const second = (word >> 16) & 0x07ff;
    return bits.signExtend32((first << 12) | (second << 1), 23);
}

fn thumbPcWrite(value: u32) u32 {
    return value & 0xfffffffe;
}

fn loadWritePc(state: *arm_state.MachineState, value: u32) void {
    if ((value & 1) != 0) {
        state.setThumb(true);
        state.write(.pc, value & 0xfffffffe);
    } else {
        state.setThumb(false);
        state.write(.pc, value & 0xfffffffc);
    }
}

fn updateNz(state: *arm_state.MachineState, value: u32) void {
    state.setNegative(bits.topBit(value));
    state.setZero(bits.isZero(value));
}
