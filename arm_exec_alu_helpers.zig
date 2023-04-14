const arm_state = @import("arm_state.zig");
const arm_registers = @import("arm_exec_register_memory.zig");
const armReg = arm_registers.armReg;
const loadWritePc = arm_registers.loadWritePc;
const nextArmReg = arm_registers.nextArmReg;
const readArmOperand = arm_registers.readArmOperand;
const writeArmAluPc = arm_registers.writeArmAluPc;
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
const arm_fetch_decode = @import("arm_exec_fetch_decode.zig");
const expandArmImmediate = arm_fetch_decode.expandArmImmediate;
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
usingnamespace @import("arm_exec_immediate_run.zig");
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");
const arm_scalar_bits = @import("arm_exec_scalar_bits.zig");
const addWithCarry = arm_scalar_bits.addWithCarry;
const arithmeticRight = arm_scalar_bits.arithmeticRight;
const logicalLeft = arm_scalar_bits.logicalLeft;
const logicalRight = arm_scalar_bits.logicalRight;
const rotateRight = arm_scalar_bits.rotateRight;
const subWithCarry = arm_scalar_bits.subWithCarry;

pub fn dataOperand(word: u32, state: *const arm_state.MachineState, pc: u32) ShiftResult {
    if (bits.getBit32(word, 25)) {
        const rotate = @intCast(u8, (word >> 8) & 0xf);
        const value = @intCast(u8, word & 0xff);
        const expanded = expandArmImmediate(rotate, value);
        return ShiftResult{
            .word = expanded,
            .carry = if (rotate == 0) state.carry() else bits.topBit(expanded),
        };
    }

    const source = armReg(word);
    const mode = @intToEnum(ShiftMode, @intCast(u2, (word >> 5) & 0x3));
    const value = readArmOperand(state, source, pc);
    if (bits.getBit32(word, 4)) {
        const amount_reg = armReg(word >> 8);
        const amount = @intCast(u8, readArmOperand(state, amount_reg, pc) & 0xff);
        return shiftByRegister(value, mode, amount, state.carry());
    }

    const amount = @intCast(u8, (word >> 7) & 0x1f);
    return shiftByImmediate(value, mode, amount, state.carry());
}

pub fn shiftByImmediate(value: u32, mode: ShiftMode, amount: u8, carry_in: bool) ShiftResult {
    return switch (mode) {
        .left => logicalLeft(value, amount, carry_in),
        .right => logicalRight(value, if (amount == 0) 32 else amount, carry_in),
        .signed_right => arithmeticRight(value, if (amount == 0) 32 else amount, carry_in),
        .rotate_right => if (amount == 0) carryRotate(value, carry_in) else rotateRight(value, amount, carry_in),
    };
}

pub fn shiftByRegister(value: u32, mode: ShiftMode, amount: u8, carry_in: bool) ShiftResult {
    return switch (mode) {
        .left => logicalLeft(value, amount, carry_in),
        .right => logicalRight(value, amount, carry_in),
        .signed_right => arithmeticRight(value, amount, carry_in),
        .rotate_right => rotateRight(value, amount, carry_in),
    };
}

pub fn carryRotate(value: u32, carry_in: bool) ShiftResult {
    const result = bits.rotateRightThroughCarry(value, carry_in);
    return ShiftResult{
        .word = result.word,
        .carry = result.carry,
    };
}

pub fn writeLogicalResult(state: *arm_state.MachineState, pc: u32, dest: arm_state.ArmReg, value: u32, carry: bool, set_flags: bool) ArmStepError!void {
    if (dest == .pc) {
        if (set_flags) {
            return error.Unpredictable;
        }
        writeArmAluPc(state, value);
        return;
    }
    state.write(dest, value);
    if (set_flags) {
        writeLogicalFlags(state, value, carry);
    }
    state.write(.pc, pc + 4);
}

pub fn writeMathResult(state: *arm_state.MachineState, pc: u32, dest: arm_state.ArmReg, result: AddResult, set_flags: bool) ArmStepError!void {
    if (dest == .pc) {
        if (set_flags) {
            return error.Unpredictable;
        }
        writeArmAluPc(state, result.word);
        return;
    }
    state.write(dest, result.word);
    if (set_flags) {
        writeMathFlags(state, result);
    }
    state.write(.pc, pc + 4);
}

pub fn writeLogicalFlags(state: *arm_state.MachineState, value: u32, carry: bool) void {
    state.setNegative(bits.topBit(value));
    state.setZero(value == 0);
    state.setCarry(carry);
}

pub fn writeMathFlags(state: *arm_state.MachineState, result: AddResult) void {
    state.setNegative(bits.topBit(result.word));
    state.setZero(result.word == 0);
    state.setCarry(result.carry);
    state.setOverflow(result.overflow);
}

pub fn writeMultiplyFlags(state: *arm_state.MachineState, value: u32) void {
    state.setNegative(bits.topBit(value));
    state.setZero(value == 0);
}

pub fn writeLongMultiplyFlags(state: *arm_state.MachineState, value: u64) void {
    state.setNegative((value & 0x8000000000000000) != 0);
    state.setZero(value == 0);
}

pub fn raiseQFlag(state: *arm_state.MachineState) void {
    state.cpsr = bits.setBit32(state.cpsr, 27, true);
}

pub fn signedSaturatingAddWord(left: u32, right: u32) SaturatingWordResult {
    const sum = addWithCarry(left, right, false);
    if (!sum.overflow) {
        return SaturatingWordResult{ .word = sum.word, .overflow = false };
    }
    const word = if ((left & 0x80000000) != 0) @as(u32, 0x80000000) else @as(u32, 0x7fffffff);
    return SaturatingWordResult{ .word = word, .overflow = true };
}

pub fn signedSaturatingSubWord(left: u32, right: u32) SaturatingWordResult {
    const difference = subWithCarry(left, right, true);
    if (!difference.overflow) {
        return SaturatingWordResult{ .word = difference.word, .overflow = false };
    }
    const word = if ((left & 0x80000000) != 0) @as(u32, 0x80000000) else @as(u32, 0x7fffffff);
    return SaturatingWordResult{ .word = word, .overflow = true };
}

pub fn unsignedSaturateWord(value: u32, amount: u8) SaturatingWordResult {
    const signed_value = @as(i64, @bitCast(i32, value));
    const limit = (@as(i64, 1) << @intCast(u6, amount)) - 1;
    if (signed_value < 0) {
        return SaturatingWordResult{ .word = 0, .overflow = true };
    }
    if (signed_value > limit) {
        return SaturatingWordResult{ .word = @intCast(u32, limit), .overflow = true };
    }
    return SaturatingWordResult{ .word = value, .overflow = false };
}

pub fn signedSaturateWord(value: u32, amount: u8) SaturatingWordResult {
    if (amount == 32) {
        return SaturatingWordResult{ .word = value, .overflow = false };
    }
    const signed_value = @as(i64, @bitCast(i32, value));
    const limit = @as(i64, 1) << @intCast(u6, amount - 1);
    const high = limit - 1;
    const low = -limit;
    if (signed_value > high) {
        return SaturatingWordResult{ .word = @intCast(u32, high), .overflow = true };
    }
    if (signed_value < low) {
        return SaturatingWordResult{ .word = @bitCast(u32, @intCast(i32, low)), .overflow = true };
    }
    return SaturatingWordResult{ .word = value, .overflow = false };
}
