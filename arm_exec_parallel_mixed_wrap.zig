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
usingnamespace @import("arm_exec_data_transfer.zig");
usingnamespace @import("arm_exec_saturate_scalar.zig");
usingnamespace @import("arm_exec_parallel_saturate.zig");
usingnamespace @import("arm_exec_parallel_halve.zig");
usingnamespace @import("arm_exec_memory_run.zig");
usingnamespace @import("arm_exec_transfer_checks.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
usingnamespace @import("arm_exec_immediate_run.zig");
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");

pub fn runUnsignedWrappingMixedHalves(word: u32, state: *arm_state.MachineState, pc: u32, add_sub: bool) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    const left_low = left & 0xffff;
    const left_high = (left >> 16) & 0xffff;
    const right_low = right & 0xffff;
    const right_high = (right >> 16) & 0xffff;
    const low_lane = if (add_sub)
        left_low -% right_high
    else
        left_low +% right_high;
    const high_lane = if (add_sub)
        left_high +% right_low
    else
        left_high -% right_low;
    var ge: u32 = 0;
    if (add_sub) {
        if (left_low >= right_high) {
            ge |= 0x3;
        }
        if (left_high + right_low >= 0x10000) {
            ge |= 0xc;
        }
    } else {
        if (left_low + right_high >= 0x10000) {
            ge |= 0x3;
        }
        if (left_high >= right_low) {
            ge |= 0xc;
        }
    }
    state.write(dest, (low_lane & 0xffff) | ((high_lane & 0xffff) << 16));
    state.writeGreaterEqualLanes(ge);
    state.write(.pc, pc + 4);
}

pub fn runSignedWrappingMixedHalves(word: u32, state: *arm_state.MachineState, pc: u32, add_sub: bool) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    const left_low = signedHalf(left);
    const left_high = signedHalf(left >> 16);
    const right_low = signedHalf(right);
    const right_high = signedHalf(right >> 16);
    const low_lane = if (add_sub)
        left_low - right_high
    else
        left_low + right_high;
    const high_lane = if (add_sub)
        left_high + right_low
    else
        left_high - right_low;
    const low = if (low_lane < 0) @intCast(u16, low_lane + 65536) else @intCast(u16, low_lane);
    const high = if (high_lane < 0) @intCast(u16, high_lane + 65536) else @intCast(u16, high_lane);
    var ge: u32 = 0;
    if (low_lane >= 0) {
        ge |= 0x3;
    }
    if (high_lane >= 0) {
        ge |= 0xc;
    }
    state.write(dest, @as(u32, low) | (@as(u32, high) << 16));
    state.writeGreaterEqualLanes(ge);
    state.write(.pc, pc + 4);
}
