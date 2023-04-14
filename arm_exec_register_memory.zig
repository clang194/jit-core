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
usingnamespace @import("arm_exec_memory_run.zig");
usingnamespace @import("arm_exec_transfer_checks.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
usingnamespace @import("arm_exec_immediate_run.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");
const arm_scalar_bits = @import("arm_exec_scalar_bits.zig");
const byteReverseHalf = arm_scalar_bits.byteReverseHalf;
const byteReverseWord = arm_scalar_bits.byteReverseWord;

pub fn armReg(value: u32) arm_state.ArmReg {
    return @intToEnum(arm_state.ArmReg, @intCast(u8, value & 0xf));
}

pub fn coprocessorReg(value: u32) arm_state.CoprocessorReg {
    return @intToEnum(arm_state.CoprocessorReg, @intCast(u4, value & 0xf));
}

pub fn nextArmReg(reg: arm_state.ArmReg) arm_state.ArmReg {
    const next = @enumToInt(reg) + 1;
    if (next >= 15) {
        return .pc;
    }
    return @intToEnum(arm_state.ArmReg, @intCast(u8, next));
}

pub fn exclusiveHolds(state: *const arm_state.MachineState, address: u32) bool {
    return state.exclusive and (((address ^ state.exclusive_address) & 0xfffffff8) == 0);
}

pub fn readArmOperand(state: *const arm_state.MachineState, reg: arm_state.ArmReg, pc: u32) u32 {
    if (reg == .pc) {
        return pc + 8;
    }
    return state.read(reg);
}

pub fn writeArmAluPc(state: *arm_state.MachineState, value: u32) void {
    state.write(.pc, value & 0xfffffffc);
}

pub fn loadWritePc(state: *arm_state.MachineState, value: u32) void {
    if ((value & 1) != 0) {
        state.setThumb(true);
        state.write(.pc, value & 0xfffffffe);
    } else {
        state.setThumb(false);
        state.write(.pc, value & 0xfffffffc);
    }
}

pub fn readMemory32(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32) ArmStepError!u32 {
    var value = if (hooks.memory.readDirect32(address)) |direct| direct else blk: {
        const read32 = hooks.memory.read32 orelse return error.MissingRead;
        break :blk read32(address);
    };
    if (state.bigEndian()) {
        value = byteReverseWord(value);
    }
    return value;
}

pub fn readMemory8(hooks: arm_state.HostHooks, address: u32) ArmStepError!u8 {
    if (hooks.memory.readDirect8(address)) |value| {
        return value;
    }
    const read8 = hooks.memory.read8 orelse return error.MissingRead;
    return read8(address);
}

pub fn readMemory16(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32) ArmStepError!u16 {
    var value = if (hooks.memory.readDirect16(address)) |direct| direct else blk: {
        const read16 = hooks.memory.read16 orelse return error.MissingRead;
        break :blk read16(address);
    };
    if (state.bigEndian()) {
        value = @intCast(u16, byteReverseHalf(value));
    }
    return value;
}

pub fn writeMemory32(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32, value: u32) ArmStepError!void {
    var data = value;
    if (state.bigEndian()) {
        data = byteReverseWord(data);
    }
    if (hooks.memory.writeDirect32(address, data)) {
        return;
    }
    const write32 = hooks.memory.write32 orelse return error.MissingWrite;
    write32(address, data);
}

pub fn writeMemory16(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32, value: u16) ArmStepError!void {
    var data = value;
    if (state.bigEndian()) {
        data = @intCast(u16, byteReverseHalf(data));
    }
    if (hooks.memory.writeDirect16(address, data)) {
        return;
    }
    const write16 = hooks.memory.write16 orelse return error.MissingWrite;
    write16(address, data);
}

pub fn writeMemory8(hooks: arm_state.HostHooks, address: u32, value: u8) ArmStepError!void {
    if (hooks.memory.writeDirect8(address, value)) {
        return;
    }
    const write8 = hooks.memory.write8 orelse return error.MissingWrite;
    write8(address, value);
}
