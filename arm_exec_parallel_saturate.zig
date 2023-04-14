const arm_state = @import("arm_state.zig");
const arm_scalar = @import("arm_exec_scalar_bits.zig");
const signedByte = arm_scalar.signedByte;
const signedHalf = arm_scalar.signedHalf;
const arm_coprocessor = @import("arm_exec_coprocessor.zig");
const armCondition = arm_coprocessor.armCondition;
const runExternalArmHandler = arm_coprocessor.runExternalArmHandler;
const arm_registers = @import("arm_exec_register_memory.zig");
const armReg = arm_registers.armReg;
const loadWritePc = arm_registers.loadWritePc;
const nextArmReg = arm_registers.nextArmReg;
const readArmOperand = arm_registers.readArmOperand;
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
usingnamespace @import("arm_exec_parallel_halve.zig");
usingnamespace @import("arm_exec_parallel_wrap.zig");
usingnamespace @import("arm_exec_memory_run.zig");
usingnamespace @import("arm_exec_transfer_checks.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
usingnamespace @import("arm_exec_immediate_run.zig");
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");

pub fn runUnsignedSaturatingSubBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        const left_byte = @intCast(u8, (left >> shift) & 0xff);
        const right_byte = @intCast(u8, (right >> shift) & 0xff);
        const byte = if (left_byte > right_byte) left_byte - right_byte else 0;
        result |= @as(u32, byte) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runSignedSaturatingSubBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        const lane = clampSignedByte(signedByte(left >> shift) - signedByte(right >> shift));
        const encoded = if (lane < 0) @intCast(u8, lane + 256) else @intCast(u8, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runUnsignedSaturatingAddBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        const left_byte = (left >> shift) & 0xff;
        const right_byte = (right >> shift) & 0xff;
        const sum = left_byte + right_byte;
        const byte = if (sum > 0xff) @as(u32, 0xff) else sum;
        result |= byte << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runSignedSaturatingAddBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        const lane = clampSignedByte(signedByte(left >> shift) + signedByte(right >> shift));
        const encoded = if (lane < 0) @intCast(u8, lane + 256) else @intCast(u8, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runUnsignedSaturatingSubHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        const left_half = @intCast(u16, (left >> shift) & 0xffff);
        const right_half = @intCast(u16, (right >> shift) & 0xffff);
        const half = if (left_half > right_half) left_half - right_half else 0;
        result |= @as(u32, half) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runSignedSaturatingSubHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        const lane = clampSignedHalfWord(signedHalf(left >> shift) - signedHalf(right >> shift));
        const encoded = if (lane < 0) @intCast(u16, lane + 65536) else @intCast(u16, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runUnsignedSaturatingAddHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        const left_half = (left >> shift) & 0xffff;
        const right_half = (right >> shift) & 0xffff;
        const sum = left_half + right_half;
        const half = if (sum > 0xffff) @as(u32, 0xffff) else sum;
        result |= half << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runSignedSaturatingAddHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        const lane = clampSignedHalfWord(signedHalf(left >> shift) + signedHalf(right >> shift));
        const encoded = if (lane < 0) @intCast(u16, lane + 65536) else @intCast(u16, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runUnsignedSaturatingMixedHalves(word: u32, state: *arm_state.MachineState, pc: u32, add_sub: bool) ArmStepError!void {
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
        left_low - right_high
    else
        left_low + right_high;
    const high_lane = if (add_sub)
        left_high + right_low
    else
        left_high - right_low;
    const low = clampUnsignedHalfWord(low_lane);
    const high = clampUnsignedHalfWord(high_lane);
    state.write(dest, @as(u32, low) | (@as(u32, high) << 16));
    state.write(.pc, pc + 4);
}

pub fn runSignedSaturatingMixedHalves(word: u32, state: *arm_state.MachineState, pc: u32, add_sub: bool) ArmStepError!void {
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
    const low_clamped = clampSignedHalfWord(low_lane);
    const high_clamped = clampSignedHalfWord(high_lane);
    const low = if (low_clamped < 0) @intCast(u16, low_clamped + 65536) else @intCast(u16, low_clamped);
    const high = if (high_clamped < 0) @intCast(u16, high_clamped + 65536) else @intCast(u16, high_clamped);
    state.write(dest, @as(u32, low) | (@as(u32, high) << 16));
    state.write(.pc, pc + 4);
}
