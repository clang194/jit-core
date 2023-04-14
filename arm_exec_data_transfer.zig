const arm_state = @import("arm_state.zig");
const arm_types = @import("arm_exec_types.zig");
const ArmStepError = arm_types.ArmStepError;
const AddResult = arm_types.AddResult;
const CoprocessorOp = arm_types.CoprocessorOp;
const DataOp = arm_types.DataOp;
const DualMultiplyOp = arm_types.DualMultiplyOp;
const ExtendOp = arm_types.ExtendOp;
const FloatBinaryOp = arm_types.FloatBinaryOp;
const FloatUnaryOp = arm_types.FloatUnaryOp;
const FloatVectorPlan = arm_types.FloatVectorPlan;
const HalfMultiplyOp = arm_types.HalfMultiplyOp;
const MultiplyOp = arm_types.MultiplyOp;
const SaturatingWordResult = arm_types.SaturatingWordResult;
const ShiftMode = arm_types.ShiftMode;
const ShiftResult = arm_types.ShiftResult;
const bits = @import("bits.zig");
usingnamespace @import("arm_exec_types.zig");
usingnamespace @import("arm_exec_fetch_decode.zig");
usingnamespace @import("arm_exec_dispatch.zig");
usingnamespace @import("arm_exec_coprocessor.zig");
usingnamespace @import("arm_exec_float_decode.zig");
usingnamespace @import("arm_exec_float_run.zig");
usingnamespace @import("arm_exec_multiply_run.zig");
usingnamespace @import("arm_exec_float_math.zig");
usingnamespace @import("arm_exec_status_branch.zig");
usingnamespace @import("arm_exec_saturate_scalar.zig");
usingnamespace @import("arm_exec_parallel_saturate.zig");
usingnamespace @import("arm_exec_parallel_halve.zig");
usingnamespace @import("arm_exec_parallel_wrap.zig");
usingnamespace @import("arm_exec_memory_run.zig");
usingnamespace @import("arm_exec_transfer_checks.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
usingnamespace @import("arm_exec_immediate_run.zig");
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");

pub fn runDataProcessing(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        .reverse_sub => try writeMathResult(state, pc, dest, subWithCarry(operand.word, left, true), set_flags),
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
    }

    switch (op) {
        .test_and, .test_xor, .compare, .compare_negative => state.write(.pc, pc + 4),
        else => {},
    }
}

pub fn runMultiply(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const op = multiplyOp(word).?;
    const code = armCondition(word).?;
    const set_flags = bits.getBit32(word, 20);
    const high = armReg(word >> 16);
    const low = armReg(word >> 12);
    const left = armReg(word);
    const right = armReg(word >> 8);

    if (high == .pc or left == .pc or right == .pc) {
        return error.Unpredictable;
    }
    switch (op) {
        .multiply_add, .multiply_subtract => {
            if (low == .pc) {
                return error.Unpredictable;
            }
        },
        .multiply => {},
        else => {
            if (low == .pc or low == high) {
                return error.Unpredictable;
            }
        },
    }

    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    switch (op) {
        .multiply => {
            const result = state.read(left) *% state.read(right);
            state.write(high, result);
            if (set_flags) {
                writeMultiplyFlags(state, result);
            }
        },
        .multiply_add => {
            const addend = readArmOperand(state, low, pc);
            const result = (state.read(left) *% state.read(right)) +% addend;
            state.write(high, result);
            if (set_flags) {
                writeMultiplyFlags(state, result);
            }
        },
        .multiply_subtract => {
            const addend = readArmOperand(state, low, pc);
            const result = addend -% (state.read(left) *% state.read(right));
            state.write(high, result);
        },
        .unsigned_long => {
            const result = @as(u64, state.read(left)) * @as(u64, state.read(right));
            writeLongResult(state, high, low, result);
            if (set_flags) {
                writeLongMultiplyFlags(state, result);
            }
        },
        .unsigned_long_add => {
            const result = (@as(u64, state.read(left)) * @as(u64, state.read(right))) +% readLong(state, high, low);
            writeLongResult(state, high, low, result);
            if (set_flags) {
                writeLongMultiplyFlags(state, result);
            }
        },
        .unsigned_accumulate => {
            const result = (@as(u64, state.read(left)) * @as(u64, state.read(right))) +% @as(u64, state.read(high)) +% @as(u64, state.read(low));
            writeLongResult(state, high, low, result);
        },
        .signed_long => {
            const result = signedProduct(state.read(left), state.read(right));
            writeLongResult(state, high, low, result);
            if (set_flags) {
                writeLongMultiplyFlags(state, result);
            }
        },
        .signed_long_add => {
            const result = signedProduct(state.read(left), state.read(right)) +% readLong(state, high, low);
            writeLongResult(state, high, low, result);
            if (set_flags) {
                writeLongMultiplyFlags(state, result);
            }
        },
    }
    state.write(.pc, pc + 4);
}

pub fn runExtend(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const op = extendOp(word).?;
    const dest = armReg(word >> 12);
    const source = armReg(word);
    const base_reg = armReg(word >> 16);
    if (dest == .pc or source == .pc) {
        return error.Unpredictable;
    }
    if (op == .unsigned_byte_pair_add and base_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const rotated = rotateRightWord(state.read(source), @intCast(u8, ((word >> 10) & 0x3) * 8));
    const base = readArmOperand(state, base_reg, pc);
    const result = switch (op) {
        .signed_byte_pair_add => addHalfPairs(base, signExtendBytePairs(rotated)),
        .signed_byte_add => base +% signExtendByte(rotated),
        .signed_half_add => base +% signExtendHalf(rotated),
        .signed_byte_pair => signExtendBytePairs(rotated),
        .signed_byte => signExtendByte(rotated),
        .signed_half => signExtendHalf(rotated),
        .unsigned_byte_pair => rotated & 0x00ff00ff,
        .unsigned_byte_pair_add => addHalfPairs(base, rotated & 0x00ff00ff),
        .unsigned_byte_add => base +% (rotated & 0xff),
        .unsigned_half_add => base +% (rotated & 0xffff),
        .unsigned_byte => rotated & 0xff,
        .unsigned_half => rotated & 0xffff,
    };
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runLoadMultiple(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const base_reg = armReg(word >> 16);
    const list = @intCast(u16, word & 0xffff);
    const count = regListCount(list);
    if (base_reg == .pc or count == 0) {
        return error.Unpredictable;
    }
    if (bits.getBit32(word, 21) and (list & (@as(u16, 1) << @intCast(u4, @enumToInt(base_reg)))) != 0) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const base = state.read(base_reg);
    const span = @as(u32, count) * 4;
    const start = if (bits.getBit32(word, 24))
        if (bits.getBit32(word, 23)) base +% 4 else base -% span
    else if (bits.getBit32(word, 23)) base else base -% span +% 4;
    const writeback = if (bits.getBit32(word, 24))
        if (bits.getBit32(word, 23)) base +% span else base -% span
    else if (bits.getBit32(word, 23)) base +% span else start -% 4;

    var address = start;
    var index: u5 = 0;
    while (index < 15) : (index += 1) {
        if ((list & (@as(u16, 1) << index)) != 0) {
            state.write(@intToEnum(arm_state.ArmReg, @intCast(u8, index)), try readMemory32(state, hooks, address));
            address +%= 4;
        }
    }

    if (bits.getBit32(word, 21) and (list & (@as(u16, 1) << @enumToInt(base_reg))) == 0) {
        state.write(base_reg, writeback);
    }

    if ((list & 0x8000) != 0) {
        loadWritePc(state, try readMemory32(state, hooks, address));
        return;
    }
    state.write(.pc, pc + 4);
}

pub fn runStoreMultiple(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const base_reg = armReg(word >> 16);
    const list = @intCast(u16, word & 0xffff);
    const count = regListCount(list);
    if (base_reg == .pc or count == 0) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const base = state.read(base_reg);
    const span = @as(u32, count) * 4;
    const start = if (bits.getBit32(word, 24))
        if (bits.getBit32(word, 23)) base +% 4 else base -% span
    else if (bits.getBit32(word, 23)) base else base -% span +% 4;
    const writeback = if (bits.getBit32(word, 24))
        if (bits.getBit32(word, 23)) base +% span else base -% span
    else if (bits.getBit32(word, 23)) base +% span else start -% 4;

    var address = start;
    var index: u5 = 0;
    while (index < 15) : (index += 1) {
        if ((list & (@as(u16, 1) << index)) != 0) {
            try writeMemory32(state, hooks, address, state.read(@intToEnum(arm_state.ArmReg, @intCast(u8, index))));
            address +%= 4;
        }
    }

    if (bits.getBit32(word, 21)) {
        state.write(base_reg, writeback);
    }

    if ((list & 0x8000) != 0) {
        try writeMemory32(state, hooks, address, pc);
    }
    state.write(.pc, pc + 4);
}
