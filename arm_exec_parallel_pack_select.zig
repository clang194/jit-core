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

pub fn runByteSelect(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

    const mask = byteSelectMask(state.readGreaterEqualLanes());
    const left = state.read(left_reg);
    const right = state.read(right_reg);
    state.write(dest, (left & mask) | (right & ~mask));
    state.write(.pc, pc + 4);
}

pub fn runUnsignedAbsDiffSum(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 16);
    const addend = armReg(word >> 12);
    const right_reg = armReg(word >> 8);
    const left_reg = armReg(word);
    const with_addend = (word & 0x0000f000) != 0x0000f000;
    if (dest == .pc or left_reg == .pc or right_reg == .pc or (with_addend and addend == .pc)) {
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
        result += if (left_byte > right_byte) left_byte - right_byte else right_byte - left_byte;
    }
    if (with_addend) {
        result +%= state.read(addend);
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn byteSelectMask(lanes: u32) u32 {
    var mask: u32 = 0;
    var index: u5 = 0;
    while (index < 4) : (index += 1) {
        if ((lanes & (@as(u32, 1) << index)) != 0) {
            mask |= @as(u32, 0xff) << @intCast(u5, index * 8);
        }
    }
    return mask;
}

pub fn runHalfwordPack(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const base_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (base_reg == .pc or dest == .pc or source == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const amount = @intCast(u8, (word >> 7) & 0x1f);
    const top = (word & 0x00000040) != 0;
    const shifted = shiftByImmediate(
        state.read(source),
        if (top) ShiftMode.signed_right else ShiftMode.left,
        amount,
        state.carry(),
    ).word;
    const base = state.read(base_reg);
    const result = if (top)
        (base & 0xffff0000) | (shifted & 0x0000ffff)
    else
        (base & 0x0000ffff) | (shifted & 0xffff0000);
    state.write(dest, result);
    state.write(.pc, pc + 4);
}
