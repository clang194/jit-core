const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");

pub const RunError = error{
    UnknownInstruction,
    Full,
    MissingRead,
};

pub const ShiftResult = struct {
    word: u32,
    carry: bool,
};

pub const ThumbWord = struct {
    word: u16,
    size: u8,
};

pub fn readThumbWord(hooks: arm_state.HostHooks, pc: u32) RunError!ThumbWord {
    if (hooks.read32 == null) {
        return error.MissingRead;
    }

    var first = hooks.read32.?(pc & 0xfffffffc);
    if ((pc & 2) != 0) {
        first >>= 16;
    }

    const word = @intCast(u16, first & 0xffff);
    if ((word & 0xf800) != 0xe800 and (word & 0xf000) != 0xf000) {
        return ThumbWord{ .word = word, .size = 2 };
    }

    return error.UnknownInstruction;
}

pub fn isStop(word: u16) bool {
    return (word & 0xff00) == 0xde00;
}

pub fn buildThumbTrace(word: u16, tape: *trace.Tape) RunError!void {
    if (isStop(word)) {
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

    return error.UnknownInstruction;
}

pub fn runThumb(word: u16, state: *arm_state.MachineState) RunError!void {
    if (isStop(word)) {
        return;
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

fn updateNz(state: *arm_state.MachineState, value: u32) void {
    state.setNegative(bits.topBit(value));
    state.setZero(bits.isZero(value));
}

