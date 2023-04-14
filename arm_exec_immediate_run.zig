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
usingnamespace @import("arm_exec_saturate_scalar.zig");
usingnamespace @import("arm_exec_parallel_saturate.zig");
usingnamespace @import("arm_exec_parallel_halve.zig");
usingnamespace @import("arm_exec_parallel_wrap.zig");
usingnamespace @import("arm_exec_memory_run.zig");
usingnamespace @import("arm_exec_transfer_checks.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");

pub fn runAdcImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

pub fn runCmpImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

pub fn runRev(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

pub fn runRevHalfwords(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

pub fn runRevSignedHalf(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

pub fn runBitReverse(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (dest == .pc or source == .pc) {
        return error.Unpredictable;
    }
    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.write(dest, reverseBitsWord(state.read(source)));
    }
    state.write(.pc, pc + 4);
}

pub fn runBitfieldClear(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const msb = @intCast(u5, (word >> 16) & 0x1f);
    const dest = armReg(word >> 12);
    const lsb = @intCast(u5, (word >> 7) & 0x1f);
    if (dest == .pc or msb < lsb) {
        return error.Unpredictable;
    }
    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const width = @as(u32, msb) - @as(u32, lsb) + 1;
        const ones = lowMask32(@intCast(u6, width));
        state.write(dest, state.read(dest) & ~(ones << lsb));
    }
    state.write(.pc, pc + 4);
}

pub fn runBitfieldInsert(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const msb = @intCast(u5, (word >> 16) & 0x1f);
    const dest = armReg(word >> 12);
    const lsb = @intCast(u5, (word >> 7) & 0x1f);
    const source = armReg(word);
    if (dest == .pc or msb < lsb) {
        return error.Unpredictable;
    }
    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const width = @as(u32, msb) - @as(u32, lsb) + 1;
        const mask = lowMask32(@intCast(u6, width)) << lsb;
        const kept = state.read(dest) & ~mask;
        const inserted = (state.read(source) << lsb) & mask;
        state.write(dest, kept | inserted);
    }
    state.write(.pc, pc + 4);
}

pub fn runBitfieldExtract(word: u32, state: *arm_state.MachineState, pc: u32, signed: bool) ArmStepError!void {
    const width_minus_one = @intCast(u5, (word >> 16) & 0x1f);
    const dest = armReg(word >> 12);
    const lsb = @intCast(u5, (word >> 7) & 0x1f);
    const source = armReg(word);
    const msb = @as(u6, lsb) + @as(u6, width_minus_one);
    if (dest == .pc or source == .pc or msb >= 32) {
        return error.Unpredictable;
    }
    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const width = @as(u6, width_minus_one) + 1;
        const extracted = (state.read(source) >> lsb) & lowMask32(width);
        const sign = (@as(u32, 1) << @intCast(u5, width - 1));
        const result = if (signed and (extracted & sign) != 0)
            extracted | ~lowMask32(width)
        else
            extracted;
        state.write(dest, result);
    }
    state.write(.pc, pc + 4);
}

pub fn runMoveTop(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    if (dest == .pc) {
        return error.Unpredictable;
    }
    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const imm16 = (((word >> 16) & 0xf) << 12) | (word & 0xfff);
        state.write(dest, (state.read(dest) & 0x0000ffff) | (imm16 << 16));
    }
    state.write(.pc, pc + 4);
}

pub fn runMoveLow(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    if (dest == .pc) {
        return error.Unpredictable;
    }
    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const imm16 = (((word >> 16) & 0xf) << 12) | (word & 0xfff);
        state.write(dest, imm16);
    }
    state.write(.pc, pc + 4);
}
