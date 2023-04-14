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
usingnamespace @import("arm_exec_parallel_wrap.zig");
usingnamespace @import("arm_exec_transfer_checks.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
usingnamespace @import("arm_exec_immediate_run.zig");
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");

pub fn runLoadExclusive(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const base_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const op = word & 0x0ff00000;
    if (base_reg == .pc or dest == .pc or (op == 0x01b00000 and dest == .lr)) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const address = state.read(base_reg);
    state.exclusive = true;
    state.exclusive_address = address;
    switch (op) {
        0x01900000 => state.write(dest, try readMemory32(state, hooks, address)),
        0x01d00000 => state.write(dest, try readMemory8(hooks, address)),
        0x01b00000 => {
            state.write(dest, try readMemory32(state, hooks, address));
            state.write(nextArmReg(dest), try readMemory32(state, hooks, address +% 4));
        },
        0x01f00000 => state.write(dest, try readMemory16(state, hooks, address)),
        else => return error.UnknownInstruction,
    }
    state.write(.pc, pc + 4);
}

pub fn runStoreExclusive(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const base_reg = armReg(word >> 16);
    const status_reg = armReg(word >> 12);
    const data_reg = armReg(word);
    const op = word & 0x0ff00000;
    if (base_reg == .pc or status_reg == .pc or status_reg == base_reg or status_reg == data_reg) {
        return error.Unpredictable;
    }
    if (op == 0x01a00000) {
        if (data_reg == .lr or (@enumToInt(data_reg) & 1) != 0 or status_reg == nextArmReg(data_reg)) {
            return error.Unpredictable;
        }
    } else if (data_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const address = state.read(base_reg);
    if (exclusiveHolds(state, address)) {
        state.exclusive = false;
        switch (op) {
            0x01800000 => try writeMemory32(state, hooks, address, state.read(data_reg)),
            0x01c00000 => try writeMemory8(hooks, address, bits.lowByte(state.read(data_reg))),
            0x01a00000 => {
                try writeMemory32(state, hooks, address, state.read(data_reg));
                try writeMemory32(state, hooks, address +% 4, state.read(nextArmReg(data_reg)));
            },
            0x01e00000 => try writeMemory16(state, hooks, address, @intCast(u16, state.read(data_reg) & 0xffff)),
            else => return error.UnknownInstruction,
        }
        state.write(status_reg, 0);
    } else {
        state.write(status_reg, 1);
    }
    state.write(.pc, pc + 4);
}

pub fn runSwap(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const base_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (base_reg == .pc or dest == .pc or source == .pc or base_reg == dest or base_reg == source) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const address = state.read(base_reg);
    if ((word & 0x00400000) != 0) {
        const data = try readMemory8(hooks, address);
        try writeMemory8(hooks, address, bits.lowByte(state.read(source)));
        state.write(dest, data);
    } else {
        const data = try readMemory32(state, hooks, address);
        try writeMemory32(state, hooks, address, state.read(source));
        state.write(dest, data);
    }
    state.write(.pc, pc + 4);
}
