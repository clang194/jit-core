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
usingnamespace @import("arm_exec_parallel_wrap.zig");
usingnamespace @import("arm_exec_memory_run.zig");
usingnamespace @import("arm_exec_transfer_checks.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
usingnamespace @import("arm_exec_immediate_run.zig");
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");

pub fn runUnsignedHalvingAddBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
    var result: u32 = 0;
    var index: u5 = 0;
    while (index < 4) : (index += 1) {
        const shift = @intCast(u5, index * 8);
        const sum = ((left >> shift) & 0xff) + ((right >> shift) & 0xff);
        result |= (sum >> 1) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runUnsignedHalvingAddHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
    var result: u32 = 0;
    var index: u5 = 0;
    while (index < 2) : (index += 1) {
        const shift = @intCast(u5, index * 16);
        const sum = ((left >> shift) & 0xffff) + ((right >> shift) & 0xffff);
        result |= (sum >> 1) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runSignedHalvingAddBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
    var result: u32 = 0;
    var index: u5 = 0;
    while (index < 4) : (index += 1) {
        const shift = @intCast(u5, index * 8);
        const lane = @divFloor(signedByte(left >> shift) + signedByte(right >> shift), 2);
        const encoded = if (lane < 0) @intCast(u8, lane + 256) else @intCast(u8, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runSignedHalvingAddHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
    var result: u32 = 0;
    var index: u5 = 0;
    while (index < 2) : (index += 1) {
        const shift = @intCast(u5, index * 16);
        const lane = @divFloor(signedHalf(left >> shift) + signedHalf(right >> shift), 2);
        const encoded = if (lane < 0) @intCast(u16, lane + 65536) else @intCast(u16, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runUnsignedHalvingMixedHalves(word: u32, state: *arm_state.MachineState, pc: u32, add_sub: bool) ArmStepError!void {
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
    const left_low = @intCast(i32, left & 0xffff);
    const left_high = @intCast(i32, (left >> 16) & 0xffff);
    const right_low = @intCast(i32, right & 0xffff);
    const right_high = @intCast(i32, (right >> 16) & 0xffff);
    const low_lane = if (add_sub)
        @divFloor(left_low - right_high, 2)
    else
        @divFloor(left_low + right_high, 2);
    const high_lane = if (add_sub)
        @divFloor(left_high + right_low, 2)
    else
        @divFloor(left_high - right_low, 2);
    const low = if (low_lane < 0) @intCast(u16, low_lane + 65536) else @intCast(u16, low_lane);
    const high = if (high_lane < 0) @intCast(u16, high_lane + 65536) else @intCast(u16, high_lane);
    state.write(dest, @as(u32, low) | (@as(u32, high) << 16));
    state.write(.pc, pc + 4);
}

pub fn runSignedHalvingMixedHalves(word: u32, state: *arm_state.MachineState, pc: u32, add_sub: bool) ArmStepError!void {
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
        @divFloor(left_low - right_high, 2)
    else
        @divFloor(left_low + right_high, 2);
    const high_lane = if (add_sub)
        @divFloor(left_high + right_low, 2)
    else
        @divFloor(left_high - right_low, 2);
    const low = if (low_lane < 0) @intCast(u16, low_lane + 65536) else @intCast(u16, low_lane);
    const high = if (high_lane < 0) @intCast(u16, high_lane + 65536) else @intCast(u16, high_lane);
    state.write(dest, @as(u32, low) | (@as(u32, high) << 16));
    state.write(.pc, pc + 4);
}
