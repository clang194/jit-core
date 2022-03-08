const arm_state = @import("arm_state.zig");
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
        if (base_reg == .pc) {
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
        if (base_reg == .pc) {
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
        if (base_reg == .pc) {
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

    try writeMemory32(state, hooks, address, readArmOperand(state, first_reg, pc));
    try writeMemory32(state, hooks, address +% 4, readArmOperand(state, nextArmReg(first_reg), pc));
    state.write(.pc, pc + 4);
}

