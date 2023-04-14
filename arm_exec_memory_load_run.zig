const arm_state = @import("arm_state.zig");
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
usingnamespace @import("arm_exec_transfer_checks.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
usingnamespace @import("arm_exec_immediate_run.zig");
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");

pub fn runLoadWord(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectWordLoad(word);

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const pre_index = bits.getBit32(word, 24);
    const increase = bits.getBit32(word, 23);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const base_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const base = readArmOperand(state, base_reg, pc);
    const offset = transferWordOffset(word, state, pc);
    const changed = offsetAddress(base, offset, increase);
    const address = if (pre_index) changed else base;

    if (writeback) {
        if (base_reg == .pc) {
            return error.Unpredictable;
        }
        state.write(base_reg, changed);
    }

    const data = try readMemory32(state, hooks, address);
    if (dest == .pc) {
        loadWritePc(state, data);
        return;
    }
    state.write(dest, data);
    state.write(.pc, pc + 4);
}

pub fn runLoadByte(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectNarrowLoad(word);

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const pre_index = bits.getBit32(word, 24);
    const increase = bits.getBit32(word, 23);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const base_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const base = readArmOperand(state, base_reg, pc);
    const offset = transferWordOffset(word, state, pc);
    const changed = offsetAddress(base, offset, increase);
    const address = if (pre_index) changed else base;

    if (writeback) {
        if (base_reg == .pc) {
            return error.Unpredictable;
        }
        state.write(base_reg, changed);
    }

    const data = try readMemory8(hooks, address);
    if (dest == .pc) {
        writeArmAluPc(state, data +% 4);
        return;
    }
    state.write(dest, data);
    state.write(.pc, pc + 4);
}

pub fn runLoadHalf(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectNarrowLoad(word);

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const pre_index = bits.getBit32(word, 24);
    const increase = bits.getBit32(word, 23);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const base_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const base = readArmOperand(state, base_reg, pc);
    const offset = transferHalfOffset(word, state, pc);
    const changed = offsetAddress(base, offset, increase);
    const address = if (pre_index) changed else base;

    if (writeback) {
        if (base_reg == .pc) {
            return error.Unpredictable;
        }
        state.write(base_reg, changed);
    }

    const data = try readMemory16(state, hooks, address);
    if (dest == .pc) {
        writeArmAluPc(state, @as(u32, data) +% 4);
        return;
    }
    state.write(dest, data);
    state.write(.pc, pc + 4);
}

pub fn runLoadSignedByte(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectNarrowLoad(word);

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const pre_index = bits.getBit32(word, 24);
    const increase = bits.getBit32(word, 23);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const base_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const base = readArmOperand(state, base_reg, pc);
    const offset = transferHalfOffset(word, state, pc);
    const changed = offsetAddress(base, offset, increase);
    const address = if (pre_index) changed else base;

    if (writeback) {
        if (base_reg == .pc) {
            return error.Unpredictable;
        }
        state.write(base_reg, changed);
    }

    const data = signExtendByte(try readMemory8(hooks, address));
    if (dest == .pc) {
        writeArmAluPc(state, data +% 4);
        return;
    }
    state.write(dest, data);
    state.write(.pc, pc + 4);
}

pub fn runLoadSignedHalf(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectNarrowLoad(word);

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const pre_index = bits.getBit32(word, 24);
    const increase = bits.getBit32(word, 23);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const base_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const base = readArmOperand(state, base_reg, pc);
    const offset = transferHalfOffset(word, state, pc);
    const changed = offsetAddress(base, offset, increase);
    const address = if (pre_index) changed else base;

    if (writeback) {
        if (base_reg == .pc) {
            return error.Unpredictable;
        }
        state.write(base_reg, changed);
    }

    const data = signExtendHalf(try readMemory16(state, hooks, address));
    if (dest == .pc) {
        writeArmAluPc(state, data +% 4);
        return;
    }
    state.write(dest, data);
    state.write(.pc, pc + 4);
}

pub fn runLoadDouble(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectDoubleLoad(word);

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const pre_index = bits.getBit32(word, 24);
    const increase = bits.getBit32(word, 23);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const base_reg = armReg(word >> 16);
    const first_reg = armReg(word >> 12);
    const second_reg = nextArmReg(first_reg);
    const base = readArmOperand(state, base_reg, pc);
    const offset = transferHalfOffset(word, state, pc);
    const changed = offsetAddress(base, offset, increase);
    const address = if (pre_index) changed else base;

    if (writeback) {
        if (base_reg == .pc) {
            return error.Unpredictable;
        }
        state.write(base_reg, changed);
    }

    var first = try readMemory32(state, hooks, address);
    var second = try readMemory32(state, hooks, address +% 4);
    if (first_reg == .pc) {
        first +%= 4;
    } else if (first_reg == .lr) {
        second +%= 4;
    }

    if (first_reg == .pc) {
        writeArmAluPc(state, first);
    } else {
        state.write(first_reg, first);
    }
    if (second_reg == .pc) {
        writeArmAluPc(state, second);
    } else {
        state.write(second_reg, second);
    }
    if (first_reg != .pc and second_reg != .pc) {
        state.write(.pc, pc + 4);
    }
}
