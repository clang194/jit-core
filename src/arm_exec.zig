const arm_state = @import("arm_state.zig");
const bits = @import("bits.zig");

pub const ArmStepError = error{
    UnknownInstruction,
    Unpredictable,
    MissingRead,
};

pub const AddResult = struct {
    word: u32,
    carry: bool,
    overflow: bool,
};

pub const ShiftResult = struct {
    word: u32,
    carry: bool,
};

const DataOp = enum(u4) {
    bit_and = 0x0,
    bit_xor = 0x1,
    sub = 0x2,
    reverse_sub = 0x3,
    add = 0x4,
    add_carry = 0x5,
    sub_carry = 0x6,
    reverse_sub_carry = 0x7,
    test_and = 0x8,
    test_xor = 0x9,
    compare = 0xa,
    compare_negative = 0xb,
    bit_or = 0xc,
    move = 0xd,
    bit_clear = 0xe,
    move_not = 0xf,
};

const ShiftMode = enum(u2) {
    left,
    right,
    signed_right,
    rotate_right,
};

const ExtendOp = enum(u4) {
    signed_byte_add,
    signed_half_add,
    signed_byte,
    signed_half,
    unsigned_byte_add,
    unsigned_half_add,
    unsigned_byte,
    unsigned_half,
};

pub fn readArmWord(hooks: arm_state.HostHooks, pc: u32) ArmStepError!u32 {
    if (hooks.read32 == null) {
        return error.MissingRead;
    }
    return hooks.read32.?(pc & 0xfffffffc);
}

pub fn isSupervisorCall(word: u32) bool {
    return (word & 0x0f000000) == 0x0f000000 and armCondition(word) != null;
}

pub fn supervisorImmediate(word: u32) u32 {
    return word & 0x00ffffff;
}

pub fn isBranchImmediate(word: u32) bool {
    return (word & 0x0e000000) == 0x0a000000 and armCondition(word) != null;
}

pub fn isBranchExchange(word: u32) bool {
    return (word & 0x0ffffff0) == 0x012fff10 and armCondition(word) != null;
}

pub fn isDataProcessing(word: u32) bool {
    return dataOp(word) != null;
}

pub fn isAdcImmediate(word: u32) bool {
    return (word & 0x0fe00000) == 0x02a00000 and armCondition(word) != null;
}

pub fn isCmpImmediate(word: u32) bool {
    return (word & 0x0ff0f000) == 0x03500000 and armCondition(word) != null;
}

pub fn isRev(word: u32) bool {
    return (word & 0x0fff0ff0) == 0x06bf0f30 and armCondition(word) != null;
}

pub fn isRevHalfwords(word: u32) bool {
    return (word & 0x0fff0ff0) == 0x06bf0fb0 and armCondition(word) != null;
}

pub fn isRevSignedHalf(word: u32) bool {
    return (word & 0x0fff0ff0) == 0x06ff0fb0 and armCondition(word) != null;
}

pub fn expandArmImmediate(rotate: u8, value: u8) u32 {
    return rotateRightWord(@as(u32, value), rotate * 2);
}

pub fn runArmWord(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks) ArmStepError!void {
    const pc = state.read(.pc);
    if (isBranchImmediate(word)) {
        return runBranchImmediate(word, state, pc);
    }

    if (isBranchExchange(word)) {
        return runBranchExchange(word, state, pc);
    }

    if (isDataProcessing(word)) {
        return runDataProcessing(word, state, pc);
    }

    if (isAdcImmediate(word)) {
        return runAdcImmediate(word, state, pc);
    }

    if (isCmpImmediate(word)) {
        return runCmpImmediate(word, state, pc);
    }

    if (isRev(word)) {
        return runRev(word, state, pc);
    }

    if (isRevHalfwords(word)) {
        return runRevHalfwords(word, state, pc);
    }

    if (isRevSignedHalf(word)) {
        return runRevSignedHalf(word, state, pc);
    }

    if (extendOp(word)) |_| {
        return runExtend(word, state, pc);
    }

    if (isSupervisorCall(word)) {
        const code = armCondition(word).?;
        if (!state.conditionHolds(code)) {
            state.write(.pc, pc + 4);
            return;
        }
        if (hooks.supervisor) |callback| {
            callback(supervisorImmediate(word), state);
            if (state.read(.pc) == pc) {
                state.write(.pc, pc + 4);
            }
            return;
        }
    }

    if (hooks.fallback) |callback| {
        callback(pc, state);
        return;
    }
    return error.UnknownInstruction;
}

pub fn runArmWithHooks(state: *arm_state.MachineState, hooks: arm_state.HostHooks) ArmStepError!void {
    const pc = state.read(.pc);
    const word = readArmWord(hooks, pc) catch |err| switch (err) {
        error.MissingRead => {
            if (hooks.fallback) |callback| {
                callback(pc, state);
                return;
            }
            return err;
        },
        else => return err,
    };
    return runArmWord(word, state, hooks);
}

fn armCondition(word: u32) ?arm_state.ConditionCode {
    return arm_state.conditionFromNibble(@intCast(u4, word >> 28));
}

fn runBranchImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const offset = bits.signExtend32((word & 0x00ffffff) << 2, 26) + 8;
    if (bits.getBit32(word, 24)) {
        state.write(.lr, pc + 4);
    }
    state.write(.pc, addSigned(pc, offset));
}

fn runBranchExchange(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const source = armReg(word);
    loadWritePc(state, readArmOperand(state, source, pc));
}

fn dataOp(word: u32) ?DataOp {
    if (armCondition(word) == null) {
        return null;
    }
    if ((word & 0x0c000000) != 0) {
        return null;
    }
    const immediate = bits.getBit32(word, 25);
    if (!immediate and bits.getBit32(word, 4) and bits.getBit32(word, 7)) {
        return null;
    }
    const op = @intToEnum(DataOp, @intCast(u4, (word >> 21) & 0xf));
    const set_flags = bits.getBit32(word, 20);
    const base = (word >> 16) & 0xf;
    const dest = (word >> 12) & 0xf;
    return switch (op) {
        .reverse_sub => null,
        .test_and, .test_xor, .compare, .compare_negative => if (set_flags and dest == 0) op else null,
        .move, .move_not => if (base == 0) op else null,
        else => op,
    };
}

fn extendOp(word: u32) ?ExtendOp {
    if (armCondition(word) == null) {
        return null;
    }
    if ((word & 0x0fff03f0) == 0x06af0070) {
        return .signed_byte;
    }
    if ((word & 0x0fff03f0) == 0x06bf0070) {
        return .signed_half;
    }
    if ((word & 0x0fff03f0) == 0x06ef0070) {
        return .unsigned_byte;
    }
    if ((word & 0x0fff03f0) == 0x06ff0070) {
        return .unsigned_half;
    }
    if ((word & 0x0ff003f0) == 0x06a00070) {
        return .signed_byte_add;
    }
    if ((word & 0x0ff003f0) == 0x06b00070) {
        return .signed_half_add;
    }
    if ((word & 0x0ff003f0) == 0x06e00070) {
        return .unsigned_byte_add;
    }
    if ((word & 0x0ff003f0) == 0x06f00070) {
        return .unsigned_half_add;
    }
    return null;
}

fn runDataProcessing(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const op = dataOp(word).?;
    try rejectBadRegisterShift(word, op);

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const set_flags = bits.getBit32(word, 20);
    const base = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const operand = dataOperand(word, state, pc);
    const left = readArmOperand(state, base, pc);

    switch (op) {
        .bit_and => try writeLogicalResult(state, pc, dest, left & operand.word, operand.carry, set_flags),
        .bit_xor => try writeLogicalResult(state, pc, dest, left ^ operand.word, operand.carry, set_flags),
        .sub => try writeMathResult(state, pc, dest, subWithCarry(left, operand.word, true), set_flags),
        .add => try writeMathResult(state, pc, dest, addWithCarry(left, operand.word, false), set_flags),
        .add_carry => try writeMathResult(state, pc, dest, addWithCarry(left, operand.word, state.carry()), set_flags),
        .sub_carry => try writeMathResult(state, pc, dest, subWithCarry(left, operand.word, state.carry()), set_flags),
        .reverse_sub_carry => try writeMathResult(state, pc, dest, subWithCarry(operand.word, left, state.carry()), set_flags),
        .test_and => writeLogicalFlags(state, left & operand.word, operand.carry),
        .test_xor => writeLogicalFlags(state, left ^ operand.word, operand.carry),
        .compare => writeMathFlags(state, subWithCarry(left, operand.word, true)),
        .compare_negative => writeMathFlags(state, addWithCarry(left, operand.word, false)),
        .bit_or => try writeLogicalResult(state, pc, dest, left | operand.word, operand.carry, set_flags),
        .move => try writeLogicalResult(state, pc, dest, operand.word, operand.carry, set_flags),
        .bit_clear => try writeLogicalResult(state, pc, dest, left & ~operand.word, operand.carry, set_flags),
        .move_not => try writeLogicalResult(state, pc, dest, ~operand.word, operand.carry, set_flags),
        .reverse_sub => unreachable,
    }

    switch (op) {
        .test_and, .test_xor, .compare, .compare_negative => state.write(.pc, pc + 4),
        else => {},
    }
}

fn runExtend(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const op = extendOp(word).?;
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (dest == .pc or source == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const rotated = rotateRightWord(state.read(source), @intCast(u8, ((word >> 10) & 0x3) * 8));
    const base = readArmOperand(state, armReg(word >> 16), pc);
    const result = switch (op) {
        .signed_byte_add => base +% signExtendByte(rotated),
        .signed_half_add => base +% signExtendHalf(rotated),
        .signed_byte => signExtendByte(rotated),
        .signed_half => signExtendHalf(rotated),
        .unsigned_byte_add => base +% (rotated & 0xff),
        .unsigned_half_add => base +% (rotated & 0xffff),
        .unsigned_byte => rotated & 0xff,
        .unsigned_half => rotated & 0xffff,
    };
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

fn rejectBadRegisterShift(word: u32, op: DataOp) ArmStepError!void {
    if (bits.getBit32(word, 25) or !bits.getBit32(word, 4)) {
        return;
    }
    const base = armReg(word >> 16);
    const source = armReg(word);
    const amount = armReg(word >> 8);
    switch (op) {
        .compare, .compare_negative => return,
        .move, .move_not => {
            if (source == .pc or amount == .pc) {
                return error.Unpredictable;
            }
        },
        else => {
            if (base == .pc or source == .pc or amount == .pc) {
                return error.Unpredictable;
            }
        },
    }
}

fn dataOperand(word: u32, state: *const arm_state.MachineState, pc: u32) ShiftResult {
    if (bits.getBit32(word, 25)) {
        const rotate = @intCast(u8, (word >> 8) & 0xf);
        const value = @intCast(u8, word & 0xff);
        const expanded = expandArmImmediate(rotate, value);
        return ShiftResult{
            .word = expanded,
            .carry = if (rotate == 0) state.carry() else bits.topBit(expanded),
        };
    }

    const source = armReg(word);
    const mode = @intToEnum(ShiftMode, @intCast(u2, (word >> 5) & 0x3));
    const value = readArmOperand(state, source, pc);
    if (bits.getBit32(word, 4)) {
        const amount_reg = armReg(word >> 8);
        const amount = @intCast(u8, readArmOperand(state, amount_reg, pc) & 0xff);
        return shiftByRegister(value, mode, amount, state.carry());
    }

    const amount = @intCast(u8, (word >> 7) & 0x1f);
    return shiftByImmediate(value, mode, amount, state.carry());
}

fn shiftByImmediate(value: u32, mode: ShiftMode, amount: u8, carry_in: bool) ShiftResult {
    return switch (mode) {
        .left => logicalLeft(value, amount, carry_in),
        .right => logicalRight(value, if (amount == 0) 32 else amount, carry_in),
        .signed_right => arithmeticRight(value, if (amount == 0) 32 else amount, carry_in),
        .rotate_right => if (amount == 0) carryRotate(value, carry_in) else rotateRight(value, amount, carry_in),
    };
}

fn shiftByRegister(value: u32, mode: ShiftMode, amount: u8, carry_in: bool) ShiftResult {
    return switch (mode) {
        .left => logicalLeft(value, amount, carry_in),
        .right => logicalRight(value, amount, carry_in),
        .signed_right => arithmeticRight(value, amount, carry_in),
        .rotate_right => rotateRight(value, amount, carry_in),
    };
}

fn carryRotate(value: u32, carry_in: bool) ShiftResult {
    const result = bits.rotateRightThroughCarry(value, carry_in);
    return ShiftResult{
        .word = result.word,
        .carry = result.carry,
    };
}

fn writeLogicalResult(state: *arm_state.MachineState, pc: u32, dest: arm_state.ArmReg, value: u32, carry: bool, set_flags: bool) ArmStepError!void {
    if (dest == .pc) {
        if (set_flags) {
            return error.Unpredictable;
        }
        writeArmAluPc(state, value);
        return;
    }
    state.write(dest, value);
    if (set_flags) {
        writeLogicalFlags(state, value, carry);
    }
    state.write(.pc, pc + 4);
}

fn writeMathResult(state: *arm_state.MachineState, pc: u32, dest: arm_state.ArmReg, result: AddResult, set_flags: bool) ArmStepError!void {
    if (dest == .pc) {
        if (set_flags) {
            return error.Unpredictable;
        }
        writeArmAluPc(state, result.word);
        return;
    }
    state.write(dest, result.word);
    if (set_flags) {
        writeMathFlags(state, result);
    }
    state.write(.pc, pc + 4);
}

fn writeLogicalFlags(state: *arm_state.MachineState, value: u32, carry: bool) void {
    state.setNegative(bits.topBit(value));
    state.setZero(value == 0);
    state.setCarry(carry);
}

fn writeMathFlags(state: *arm_state.MachineState, result: AddResult) void {
    state.setNegative(bits.topBit(result.word));
    state.setZero(result.word == 0);
    state.setCarry(result.carry);
    state.setOverflow(result.overflow);
}

fn runAdcImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const set_flags = ((word >> 20) & 1) != 0;
    const base = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const rotate = @intCast(u8, (word >> 8) & 0xf);
    const imm = @intCast(u8, word & 0xff);
    const amount = expandArmImmediate(rotate, imm);
    const result = addWithCarry(readArmOperand(state, base, pc), amount, state.carry());

    if (dest == .pc) {
        if (set_flags) {
            return error.Unpredictable;
        }
        writeArmAluPc(state, result.word);
        return;
    }

    state.write(dest, result.word);
    if (set_flags) {
        state.setNegative((result.word & 0x80000000) != 0);
        state.setZero(result.word == 0);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
    }
    state.write(.pc, pc + 4);
}

fn runCmpImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const base = armReg(word >> 16);
    const rotate = @intCast(u8, (word >> 8) & 0xf);
    const imm = @intCast(u8, word & 0xff);
    const amount = expandArmImmediate(rotate, imm);
    const result = subWithCarry(readArmOperand(state, base, pc), amount, true);
    state.setNegative((result.word & 0x80000000) != 0);
    state.setZero(result.word == 0);
    state.setCarry(result.carry);
    state.setOverflow(result.overflow);
    state.write(.pc, pc + 4);
}

fn runRev(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (dest == .pc or source == .pc) {
        return error.Unpredictable;
    }
    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.write(dest, byteReverseWord(state.read(source)));
    }
    state.write(.pc, pc + 4);
}

fn runRevHalfwords(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (dest == .pc or source == .pc) {
        return error.Unpredictable;
    }
    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.write(dest, byteReverseHalfwords(state.read(source)));
    }
    state.write(.pc, pc + 4);
}

fn runRevSignedHalf(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (dest == .pc or source == .pc) {
        return error.Unpredictable;
    }
    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.write(dest, signExtendHalf(byteReverseHalf(state.read(source))));
    }
    state.write(.pc, pc + 4);
}

fn armReg(value: u32) arm_state.ArmReg {
    return @intToEnum(arm_state.ArmReg, @intCast(u8, value & 0xf));
}

fn readArmOperand(state: *const arm_state.MachineState, reg: arm_state.ArmReg, pc: u32) u32 {
    if (reg == .pc) {
        return pc + 8;
    }
    return state.read(reg);
}

fn writeArmAluPc(state: *arm_state.MachineState, value: u32) void {
    state.write(.pc, value & 0xfffffffc);
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

fn addSigned(value: u32, offset: i32) u32 {
    if (offset < 0) {
        return value -% @intCast(u32, -offset);
    }
    return value +% @intCast(u32, offset);
}

fn rotateRightWord(value: u32, amount: u8) u32 {
    const shift = amount & 31;
    if (shift == 0) {
        return value;
    }
    return (value >> @intCast(u5, shift)) | (value << @intCast(u5, 32 - shift));
}

fn logicalLeft(value: u32, amount: u8, carry_in: bool) ShiftResult {
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

fn logicalRight(value: u32, amount: u8, carry_in: bool) ShiftResult {
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

fn arithmeticRight(value: u32, amount: u8, carry_in: bool) ShiftResult {
    if (amount == 0) {
        return ShiftResult{ .word = value, .carry = carry_in };
    }
    if (amount < 32) {
        const shift = @intCast(u5, amount);
        const fill = if (bits.topBit(value)) ~(@as(u32, 0xffffffff) >> shift) else @as(u32, 0);
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

fn rotateRight(value: u32, amount: u8, carry_in: bool) ShiftResult {
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

fn byteReverseWord(value: u32) u32 {
    return ((value & 0x000000ff) << 24) |
        ((value & 0x0000ff00) << 8) |
        ((value & 0x00ff0000) >> 8) |
        ((value & 0xff000000) >> 24);
}

fn byteReverseHalf(value: u32) u32 {
    return ((value & 0xff) << 8) | ((value >> 8) & 0xff);
}

fn byteReverseHalfwords(value: u32) u32 {
    return ((value & 0x00ff00ff) << 8) | ((value & 0xff00ff00) >> 8);
}

fn signExtendByte(value: u32) u32 {
    const narrowed = value & 0xff;
    if ((narrowed & 0x80) != 0) {
        return narrowed | 0xffffff00;
    }
    return narrowed;
}

fn signExtendHalf(value: u32) u32 {
    const narrowed = value & 0xffff;
    if ((narrowed & 0x8000) != 0) {
        return narrowed | 0xffff0000;
    }
    return narrowed;
}

fn addWithCarry(left: u32, right: u32, carry_in: bool) AddResult {
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

fn subWithCarry(left: u32, right: u32, carry_in: bool) AddResult {
    return addWithCarry(left, ~right, carry_in);
}
