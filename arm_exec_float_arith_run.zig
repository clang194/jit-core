const arm_state = @import("arm_state.zig");
const arm_coprocessor = @import("arm_exec_coprocessor.zig");
const armCondition = arm_coprocessor.armCondition;
const runExternalArmHandler = arm_coprocessor.runExternalArmHandler;
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
const arm_float_math = @import("arm_exec_float_math.zig");
const addFloat32 = arm_float_math.addFloat32;
const addFloat64 = arm_float_math.addFloat64;
const advanceFloatIndex = arm_float_math.advanceFloatIndex;
const divFloat32 = arm_float_math.divFloat32;
const divFloat64 = arm_float_math.divFloat64;
const floatPairIndex = arm_float_math.floatPairIndex;
const floatVectorPlan = arm_float_math.floatVectorPlan;
const floatWordIndex = arm_float_math.floatWordIndex;
const mulFloat32 = arm_float_math.mulFloat32;
const mulFloat64 = arm_float_math.mulFloat64;
const negFloat32 = arm_float_math.negFloat32;
const negFloat64 = arm_float_math.negFloat64;
const readFloatPairAt = arm_float_math.readFloatPairAt;
const readFloatWordAt = arm_float_math.readFloatWordAt;
const sqrtFloat32 = arm_float_math.sqrtFloat32;
const sqrtFloat64 = arm_float_math.sqrtFloat64;
const subFloat32 = arm_float_math.subFloat32;
const subFloat64 = arm_float_math.subFloat64;
const writeFloatPairAt = arm_float_math.writeFloatPairAt;
const writeFloatWordAt = arm_float_math.writeFloatWordAt;
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

pub fn runFloatBinary(word: u32, state: *arm_state.MachineState, pc: u32, op: FloatBinaryOp) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        var dest = @as(u32, @enumToInt(floatPairIndex(word >> 12, bits.getBit32(word, 22))));
        var left_index = @as(u32, @enumToInt(floatPairIndex(word >> 16, bits.getBit32(word, 7))));
        var right_index = @as(u32, @enumToInt(floatPairIndex(word, bits.getBit32(word, 5))));
        const plan = try floatVectorPlan(state, true, dest, right_index);
        var index: u32 = 0;
        while (index < plan.count) : (index += 1) {
            const left = readFloatPairAt(state, left_index);
            const right = readFloatPairAt(state, right_index);
            const result = switch (op) {
                .add => addFloat64(state, left, right),
                .sub => subFloat64(state, left, right),
                .mul => mulFloat64(state, left, right),
                .neg_mul => negFloat64(mulFloat64(state, left, right)),
                .div => divFloat64(state, left, right),
            };
            writeFloatPairAt(state, dest, result);
            dest = advanceFloatIndex(dest, plan.stride, 4);
            left_index = advanceFloatIndex(left_index, plan.stride, 4);
            if (!plan.source_scalar) {
                right_index = advanceFloatIndex(right_index, plan.stride, 4);
            }
        }
    } else {
        var dest = @as(u32, @enumToInt(floatWordIndex(word >> 12, bits.getBit32(word, 22))));
        var left_index = @as(u32, @enumToInt(floatWordIndex(word >> 16, bits.getBit32(word, 7))));
        var right_index = @as(u32, @enumToInt(floatWordIndex(word, bits.getBit32(word, 5))));
        const plan = try floatVectorPlan(state, false, dest, right_index);
        var index: u32 = 0;
        while (index < plan.count) : (index += 1) {
            const left = readFloatWordAt(state, left_index);
            const right = readFloatWordAt(state, right_index);
            const result = switch (op) {
                .add => addFloat32(state, left, right),
                .sub => subFloat32(state, left, right),
                .mul => mulFloat32(state, left, right),
                .neg_mul => negFloat32(mulFloat32(state, left, right)),
                .div => divFloat32(state, left, right),
            };
            writeFloatWordAt(state, dest, result);
            dest = advanceFloatIndex(dest, plan.stride, 8);
            left_index = advanceFloatIndex(left_index, plan.stride, 8);
            if (!plan.source_scalar) {
                right_index = advanceFloatIndex(right_index, plan.stride, 8);
            }
        }
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatUnary(word: u32, state: *arm_state.MachineState, pc: u32, op: FloatUnaryOp) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        var dest = @as(u32, @enumToInt(floatPairIndex(word >> 12, bits.getBit32(word, 22))));
        var source_index = @as(u32, @enumToInt(floatPairIndex(word, bits.getBit32(word, 5))));
        const plan = try floatVectorPlan(state, true, dest, source_index);
        var index: u32 = 0;
        while (index < plan.count) : (index += 1) {
            const value = readFloatPairAt(state, source_index);
            const result = switch (op) {
                .move => value,
                .abs => value & 0x7fffffffffffffff,
                .neg => negFloat64(value),
                .sqrt => sqrtFloat64(state, value),
            };
            writeFloatPairAt(state, dest, result);
            dest = advanceFloatIndex(dest, plan.stride, 4);
            if (!plan.source_scalar) {
                source_index = advanceFloatIndex(source_index, plan.stride, 4);
            }
        }
    } else {
        var dest = @as(u32, @enumToInt(floatWordIndex(word >> 12, bits.getBit32(word, 22))));
        var source_index = @as(u32, @enumToInt(floatWordIndex(word, bits.getBit32(word, 5))));
        const plan = try floatVectorPlan(state, false, dest, source_index);
        var index: u32 = 0;
        while (index < plan.count) : (index += 1) {
            const value = readFloatWordAt(state, source_index);
            const result = switch (op) {
                .move => value,
                .abs => value & 0x7fffffff,
                .neg => negFloat32(value),
                .sqrt => sqrtFloat32(state, value),
            };
            writeFloatWordAt(state, dest, result);
            dest = advanceFloatIndex(dest, plan.stride, 8);
            if (!plan.source_scalar) {
                source_index = advanceFloatIndex(source_index, plan.stride, 8);
            }
        }
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatAdd(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatBinary(word, state, pc, .add);
}

pub fn runFloatMulAcc(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32, negate_acc: bool, negate_product: bool) ArmStepError!void {
    _ = hooks;

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        var dest = @as(u32, @enumToInt(floatPairIndex(word >> 12, bits.getBit32(word, 22))));
        var left_index = @as(u32, @enumToInt(floatPairIndex(word >> 16, bits.getBit32(word, 7))));
        var right_index = @as(u32, @enumToInt(floatPairIndex(word, bits.getBit32(word, 5))));
        const plan = try floatVectorPlan(state, true, dest, right_index);
        var index: u32 = 0;
        while (index < plan.count) : (index += 1) {
            var acc = readFloatPairAt(state, dest);
            const left = readFloatPairAt(state, left_index);
            const right = readFloatPairAt(state, right_index);
            var product = mulFloat64(state, left, right);
            if (negate_acc) {
                acc = negFloat64(acc);
            }
            if (negate_product) {
                product = negFloat64(product);
            }
            writeFloatPairAt(state, dest, addFloat64(state, acc, product));
            dest = advanceFloatIndex(dest, plan.stride, 4);
            left_index = advanceFloatIndex(left_index, plan.stride, 4);
            if (!plan.source_scalar) {
                right_index = advanceFloatIndex(right_index, plan.stride, 4);
            }
        }
    } else {
        var dest = @as(u32, @enumToInt(floatWordIndex(word >> 12, bits.getBit32(word, 22))));
        var left_index = @as(u32, @enumToInt(floatWordIndex(word >> 16, bits.getBit32(word, 7))));
        var right_index = @as(u32, @enumToInt(floatWordIndex(word, bits.getBit32(word, 5))));
        const plan = try floatVectorPlan(state, false, dest, right_index);
        var index: u32 = 0;
        while (index < plan.count) : (index += 1) {
            var acc = readFloatWordAt(state, dest);
            const left = readFloatWordAt(state, left_index);
            const right = readFloatWordAt(state, right_index);
            var product = mulFloat32(state, left, right);
            if (negate_acc) {
                acc = negFloat32(acc);
            }
            if (negate_product) {
                product = negFloat32(product);
            }
            writeFloatWordAt(state, dest, addFloat32(state, acc, product));
            dest = advanceFloatIndex(dest, plan.stride, 8);
            left_index = advanceFloatIndex(left_index, plan.stride, 8);
            if (!plan.source_scalar) {
                right_index = advanceFloatIndex(right_index, plan.stride, 8);
            }
        }
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatSub(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatBinary(word, state, pc, .sub);
}

pub fn runFloatMul(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatBinary(word, state, pc, .mul);
}

pub fn runFloatNegMul(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatBinary(word, state, pc, .neg_mul);
}

pub fn runFloatDiv(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatBinary(word, state, pc, .div);
}
