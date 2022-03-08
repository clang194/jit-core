const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_run_flow.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");
usingnamespace @import("thumb_memory_flow.zig");

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
        const source = try traceOperand(tape, arm_state.reg4(word >> 3), pc);
        _ = try tape.storeReg(link, try tape.literalWord((pc + 2) | 1));
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

