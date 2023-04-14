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
usingnamespace @import("arm_exec_float_math.zig");
usingnamespace @import("arm_exec_status_branch.zig");
usingnamespace @import("arm_exec_data_transfer.zig");
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

pub fn isSignedTopMultiply(word: u32) bool {
    return (word & 0x0ff0f0d0) == 0x0750f010 or
        (word & 0x0ff000d0) == 0x07500010 or
        (word & 0x0ff000d0) == 0x075000d0;
}

pub fn halfMultiplyOp(word: u32) ?HalfMultiplyOp {
    if (armCondition(word) == null) {
        return null;
    }
    if ((word & 0x0ff00090) == 0x01400080) {
        return .long_add;
    }
    if ((word & 0x0ff00090) == 0x01000080) {
        return .add;
    }
    if ((word & 0x0ff0f090) == 0x01600080) {
        return .multiply;
    }
    if ((word & 0x0ff000b0) == 0x01200080) {
        return .word_add;
    }
    if ((word & 0x0ff0f0b0) == 0x012000a0) {
        return .word_multiply;
    }
    return null;
}

pub fn dualMultiplyOp(word: u32) ?DualMultiplyOp {
    if (armCondition(word) == null) {
        return null;
    }
    if ((word & 0x0ff0f0d0) == 0x0700f010) {
        return .pair_add;
    }
    if ((word & 0x0ff0f0d0) == 0x0700f050) {
        return .pair_sub;
    }
    if ((word & 0x0ff000d0) == 0x07000010) {
        return .add;
    }
    if ((word & 0x0ff000d0) == 0x07400010) {
        return .long_add;
    }
    if ((word & 0x0ff000d0) == 0x07000050) {
        return .sub;
    }
    if ((word & 0x0ff000d0) == 0x07400050) {
        return .long_sub;
    }
    return null;
}

pub fn runSignedTopMultiply(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 16);
    const addend = armReg(word >> 12);
    const right = armReg(word >> 8);
    const left = armReg(word);
    const smmul = (word & 0x0ff0f0d0) == 0x0750f010;
    const subtract = (word & 0x0ff000d0) == 0x075000d0;
    if (dest == .pc or left == .pc or right == .pc or (subtract and addend == .pc)) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const product = signedProduct(state.read(left), state.read(right));
    var wide = product;
    if (!smmul) {
        const addend_wide = @as(u64, state.read(addend)) << 32;
        wide = if (subtract) addend_wide -% product else addend_wide +% product;
    }

    var result = @intCast(u32, wide >> 32);
    if (bits.getBit32(word, 5) and ((wide & (1 << 31)) != 0)) {
        result +%= 1;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runHalfMultiply(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const op = halfMultiplyOp(word).?;
    const high_or_dest = armReg(word >> 16);
    const low_or_addend = armReg(word >> 12);
    const right = armReg(word >> 8);
    const left = armReg(word);
    const left_top = bits.getBit32(word, 5);
    const right_top = bits.getBit32(word, 6);

    if (high_or_dest == .pc or left == .pc or right == .pc) {
        return error.Unpredictable;
    }
    switch (op) {
        .add, .word_add => {
            if (low_or_addend == .pc) {
                return error.Unpredictable;
            }
        },
        .long_add => {
            if (low_or_addend == .pc or low_or_addend == high_or_dest) {
                return error.Unpredictable;
            }
        },
        .multiply, .word_multiply => {},
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left_word = state.read(left);
    const right_word = state.read(right);
    const addend_word = state.read(low_or_addend);
    const addend_long = readLong(state, high_or_dest, low_or_addend);
    const left_half = selectedHalf(left_word, left_top);
    const right_half = selectedHalf(right_word, right_top);

    switch (op) {
        .long_add => {
            const product = @as(i64, left_half * right_half);
            writeLongResult(state, high_or_dest, low_or_addend, @bitCast(u64, product) +% addend_long);
        },
        .add => {
            const product = signedLowWord(@as(i64, left_half * right_half));
            const result = addWithCarry(product, addend_word, false);
            state.write(high_or_dest, result.word);
            if (result.overflow) {
                raiseQFlag(state);
            }
        },
        .multiply => {
            state.write(high_or_dest, signedLowWord(@as(i64, left_half * right_half)));
        },
        .word_add => {
            const product = (@as(i64, @bitCast(i32, left_word)) * @as(i64, right_half)) >> 16;
            const result = addWithCarry(signedLowWord(product), addend_word, false);
            state.write(high_or_dest, result.word);
            if (result.overflow) {
                raiseQFlag(state);
            }
        },
        .word_multiply => {
            const product = (@as(i64, @bitCast(i32, left_word)) * @as(i64, right_half)) >> 16;
            state.write(high_or_dest, signedLowWord(product));
        },
    }
    state.write(.pc, pc + 4);
}

pub fn runDualMultiply(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const op = dualMultiplyOp(word).?;
    const high_or_dest = armReg(word >> 16);
    const low_or_addend = armReg(word >> 12);
    const right = armReg(word >> 8);
    const left = armReg(word);
    const swap_right = bits.getBit32(word, 5);

    if (high_or_dest == .pc or left == .pc or right == .pc) {
        return error.Unpredictable;
    }
    switch (op) {
        .add, .sub => {},
        .long_add, .long_sub => {
            if (low_or_addend == .pc or low_or_addend == high_or_dest) {
                return error.Unpredictable;
            }
        },
        .pair_add, .pair_sub => {},
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left_word = state.read(left);
    const right_word = state.read(right);
    const addend_word = state.read(low_or_addend);
    const addend_long = readLong(state, high_or_dest, low_or_addend);
    const left_low = selectedHalf(left_word, false);
    const left_high = selectedHalf(left_word, true);
    const right_low = selectedHalf(right_word, swap_right);
    const right_high = selectedHalf(right_word, !swap_right);
    const product_low = signedLowWord(@as(i64, left_low * right_low));
    const product_high = signedLowWord(@as(i64, left_high * right_high));

    switch (op) {
        .add, .pair_add => {
            var sum = addWithCarry(product_low, product_high, false);
            if (sum.overflow) {
                raiseQFlag(state);
            }
            if (op == .add) {
                sum = addWithCarry(sum.word, addend_word, false);
                if (sum.overflow) {
                    raiseQFlag(state);
                }
            }
            state.write(high_or_dest, sum.word);
        },
        .sub, .pair_sub => {
            const difference = product_low -% product_high;
            if (op == .sub) {
                const sum = addWithCarry(difference, addend_word, false);
                state.write(high_or_dest, sum.word);
                if (sum.overflow) {
                    raiseQFlag(state);
                }
            } else {
                state.write(high_or_dest, difference);
            }
        },
        .long_add => {
            const product = @as(i64, left_low * right_low) + @as(i64, left_high * right_high);
            writeLongResult(state, high_or_dest, low_or_addend, @bitCast(u64, product) +% addend_long);
        },
        .long_sub => {
            const product = @as(i64, left_low * right_low) - @as(i64, left_high * right_high);
            writeLongResult(state, high_or_dest, low_or_addend, @bitCast(u64, product) +% addend_long);
        },
    }
    state.write(.pc, pc + 4);
}
