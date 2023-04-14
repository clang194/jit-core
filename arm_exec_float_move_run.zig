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
usingnamespace @import("arm_exec_multiply_run.zig");
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

pub fn runFloatMoveCoreToPairLow(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const core = armReg(word >> 12);
    if (core == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const pair = floatPairIndex(word >> 16, bits.getBit32(word, 7));
        const value = readFloatPair(state, pair) & 0xffffffff00000000;
        writeFloatPair(state, pair, value | @as(u64, state.read(core)));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMovePairLowToCore(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const core = armReg(word >> 12);
    if (core == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const value = readFloatPair(state, floatPairIndex(word >> 16, bits.getBit32(word, 7)));
        state.write(core, @intCast(u32, value & 0xffffffff));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMoveCoreToWord(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const core = armReg(word >> 12);
    if (core == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.writeFloatWord(floatWordIndex(word >> 16, bits.getBit32(word, 7)), state.read(core));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMoveWordToCore(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const core = armReg(word >> 12);
    if (core == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.write(core, state.readFloatWord(floatWordIndex(word >> 16, bits.getBit32(word, 7))));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMoveTwoCoreToTwoWord(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const second = armReg(word >> 16);
    const first = armReg(word >> 12);
    const dest = floatWordIndex(word, bits.getBit32(word, 5));
    if (first == .pc or second == .pc or isLastFloatWord(dest)) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.writeFloatWord(dest, state.read(first));
        state.writeFloatWord(nextFloatWordReg(dest), state.read(second));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMoveTwoWordToTwoCore(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const second = armReg(word >> 16);
    const first = armReg(word >> 12);
    const source = floatWordIndex(word, bits.getBit32(word, 5));
    if (first == .pc or second == .pc or first == second or isLastFloatWord(source)) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.write(first, state.readFloatWord(source));
        state.write(second, state.readFloatWord(nextFloatWordReg(source)));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMoveTwoCoreToPair(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const second = armReg(word >> 16);
    const first = armReg(word >> 12);
    if (first == .pc or second == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const value = @as(u64, state.read(first)) | (@as(u64, state.read(second)) << 32);
        writeFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)), value);
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMovePairToTwoCore(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const second = armReg(word >> 16);
    const first = armReg(word >> 12);
    if (first == .pc or second == .pc or first == second) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const value = readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
        state.write(first, @intCast(u32, value & 0xffffffff));
        state.write(second, @intCast(u32, value >> 32));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMoveReg(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatUnary(word, state, pc, .move);
}
