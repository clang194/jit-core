const arm_state = @import("arm_state.zig");
const arm_scalar = @import("arm_exec_scalar_bits.zig");
const signedByte = arm_scalar.signedByte;
const signedHalf = arm_scalar.signedHalf;
const signExtendByte = arm_scalar.signExtendByte;
const signExtendHalf = arm_scalar.signExtendHalf;
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
usingnamespace @import("arm_exec_parallel_saturate.zig");
usingnamespace @import("arm_exec_parallel_halve.zig");
usingnamespace @import("arm_exec_parallel_wrap.zig");
usingnamespace @import("arm_exec_memory_run.zig");
usingnamespace @import("arm_exec_transfer_checks.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
const arm_alu_helpers = @import("arm_exec_alu_helpers.zig");
const raiseQFlag = arm_alu_helpers.raiseQFlag;
const shiftByImmediate = arm_alu_helpers.shiftByImmediate;
const signedSaturateWord = arm_alu_helpers.signedSaturateWord;
const signedSaturatingAddWord = arm_alu_helpers.signedSaturatingAddWord;
const signedSaturatingSubWord = arm_alu_helpers.signedSaturatingSubWord;
const unsignedSaturateWord = arm_alu_helpers.unsignedSaturateWord;
usingnamespace @import("arm_exec_immediate_run.zig");
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");

pub fn runSignedSaturatingWord(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const left_reg = armReg(word);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word >> 16);
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
    const op = word & 0x0ff00ff0;
    var result = SaturatingWordResult{ .word = 0, .overflow = false };
    if (op == 0x01000050) {
        result = signedSaturatingAddWord(left, right);
    } else if (op == 0x01200050) {
        result = signedSaturatingSubWord(left, right);
    } else if (op == 0x01400050) {
        const doubled = signedSaturatingAddWord(right, right);
        result = signedSaturatingAddWord(left, doubled.word);
        if (doubled.overflow) {
            result.overflow = true;
        }
    } else {
        const doubled = signedSaturatingAddWord(right, right);
        result = signedSaturatingSubWord(left, doubled.word);
        if (doubled.overflow) {
            result.overflow = true;
        }
    }
    state.write(dest, result.word);
    if (result.overflow) {
        raiseQFlag(state);
    }
    state.write(.pc, pc + 4);
}

pub fn runScalarSaturatingMove(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

    const shifted = shiftByImmediate(
        state.read(source),
        if (bits.getBit32(word, 6)) ShiftMode.signed_right else ShiftMode.left,
        @intCast(u8, (word >> 7) & 0x1f),
        state.carry(),
    );
    const unsigned = bits.getBit32(word, 22);
    const amount = @intCast(u8, (word >> 16) & 0x1f) + if (unsigned) 0 else 1;
    const result = if (unsigned)
        unsignedSaturateWord(shifted.word, amount)
    else
        signedSaturateWord(shifted.word, amount);
    state.write(dest, result.word);
    if (result.overflow) {
        raiseQFlag(state);
    }
    state.write(.pc, pc + 4);
}

pub fn runHalfSaturatingMove(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

    const value = state.read(source);
    const unsigned = bits.getBit32(word, 22);
    const amount = @intCast(u8, (word >> 16) & 0xf) + if (unsigned) 0 else 1;
    const low = signExtendHalf(value);
    const high = signExtendHalf(value >> 16);
    const low_result = if (unsigned)
        unsignedSaturateWord(low, amount)
    else
        signedSaturateWord(low, amount);
    const high_result = if (unsigned)
        unsignedSaturateWord(high, amount)
    else
        signedSaturateWord(high, amount);
    state.write(dest, (low_result.word & 0xffff) | ((high_result.word & 0xffff) << 16));
    if (low_result.overflow or high_result.overflow) {
        raiseQFlag(state);
    }
    state.write(.pc, pc + 4);
}
