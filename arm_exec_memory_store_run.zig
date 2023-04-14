const arm_state = @import("arm_state.zig");
const arm_transfer = @import("arm_exec_transfer_checks.zig");
const isHalfTransferRegisterOffset = arm_transfer.isHalfTransferRegisterOffset;
const isTransferUserMode = arm_transfer.isTransferUserMode;
const isWordTransferRegisterOffset = arm_transfer.isWordTransferRegisterOffset;
const offsetAddress = arm_transfer.offsetAddress;
const rejectBadRegisterShift = arm_transfer.rejectBadRegisterShift;
const rejectDoubleLoad = arm_transfer.rejectDoubleLoad;
const rejectDoubleStore = arm_transfer.rejectDoubleStore;
const rejectNarrowLoad = arm_transfer.rejectNarrowLoad;
const rejectSingleStore = arm_transfer.rejectSingleStore;
const rejectWordLoad = arm_transfer.rejectWordLoad;
const transferHalfOffset = arm_transfer.transferHalfOffset;
const transferWordOffset = arm_transfer.transferWordOffset;
const transferWritesBack = arm_transfer.transferWritesBack;
const arm_coprocessor = @import("arm_exec_coprocessor.zig");
const armCondition = arm_coprocessor.armCondition;
const runExternalArmHandler = arm_coprocessor.runExternalArmHandler;
const arm_registers = @import("arm_exec_register_memory.zig");
const armReg = arm_registers.armReg;
const loadWritePc = arm_registers.loadWritePc;
const nextArmReg = arm_registers.nextArmReg;
const readArmOperand = arm_registers.readArmOperand;
const readMemory8 = arm_registers.readMemory8;
const readMemory16 = arm_registers.readMemory16;
const readMemory32 = arm_registers.readMemory32;
const writeMemory8 = arm_registers.writeMemory8;
const writeMemory16 = arm_registers.writeMemory16;
const writeMemory32 = arm_registers.writeMemory32;
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

pub fn runStoreWord(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectSingleStore(word, false, isWordTransferRegisterOffset(word));

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const pre_index = bits.getBit32(word, 24);
    const increase = bits.getBit32(word, 23);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const base_reg = armReg(word >> 16);
    const data_reg = armReg(word >> 12);
    const base = readArmOperand(state, base_reg, pc);
    const offset = transferWordOffset(word, state, pc);
    const changed = offsetAddress(base, offset, increase);
    const address = if (pre_index) changed else base;

    if (writeback) {
        if (base_reg == .pc or base_reg == data_reg) {
            return error.Unpredictable;
        }
        state.write(base_reg, changed);
    }

    try writeMemory32(state, hooks, address, readArmOperand(state, data_reg, pc));
    state.write(.pc, pc + 4);
}

pub fn runStoreByte(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectSingleStore(word, true, isWordTransferRegisterOffset(word));

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const pre_index = bits.getBit32(word, 24);
    const increase = bits.getBit32(word, 23);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const base_reg = armReg(word >> 16);
    const data_reg = armReg(word >> 12);
    const base = readArmOperand(state, base_reg, pc);
    const offset = transferWordOffset(word, state, pc);
    const changed = offsetAddress(base, offset, increase);
    const address = if (pre_index) changed else base;

    if (writeback) {
        if (base_reg == .pc or base_reg == data_reg) {
            return error.Unpredictable;
        }
        state.write(base_reg, changed);
    }

    const data = if (data_reg == .pc) bits.lowByte(pc) else bits.lowByte(state.read(data_reg));
    try writeMemory8(hooks, address, data);
    state.write(.pc, pc + 4);
}

pub fn runStoreHalf(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectSingleStore(word, true, isHalfTransferRegisterOffset(word));

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const pre_index = bits.getBit32(word, 24);
    const increase = bits.getBit32(word, 23);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const base_reg = armReg(word >> 16);
    const data_reg = armReg(word >> 12);
    const base = readArmOperand(state, base_reg, pc);
    const offset = transferHalfOffset(word, state, pc);
    const changed = offsetAddress(base, offset, increase);
    const address = if (pre_index) changed else base;

    if (writeback) {
        if (base_reg == .pc or base_reg == data_reg) {
            return error.Unpredictable;
        }
        state.write(base_reg, changed);
    }

    const data = if (data_reg == .pc) @intCast(u16, pc & 0xffff) else @intCast(u16, state.read(data_reg) & 0xffff);
    try writeMemory16(state, hooks, address, data);
    state.write(.pc, pc + 4);
}

pub fn runStoreDouble(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectDoubleStore(word);

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
        if (base_reg == .pc or base_reg == first_reg or base_reg == second_reg) {
            return error.Unpredictable;
        }
        state.write(base_reg, changed);
    }

    try writeMemory32(state, hooks, address, readArmOperand(state, first_reg, pc));
    try writeMemory32(state, hooks, address +% 4, readArmOperand(state, second_reg, pc));
    state.write(.pc, pc + 4);
}
