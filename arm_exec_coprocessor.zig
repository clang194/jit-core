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
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");

pub fn armCondition(word: u32) ?arm_state.ConditionCode {
    return arm_state.conditionFromNibble(@intCast(u4, word >> 28));
}

pub fn usesExternalArmHandler(word: u32) bool {
    for (external_arm_patterns) |pattern| {
        if ((word & pattern.mask) == pattern.expect) {
            return true;
        }
    }
    return false;
}

pub fn coprocessorOp(word: u32) ?CoprocessorOp {
    if ((word & 0xff000010) == 0xfe000000 or (word & 0x0f000010) == 0x0e000000) {
        return .command;
    }
    if ((word & 0xfe100000) == 0xfc100000 or (word & 0x0e100000) == 0x0c100000) {
        return .load;
    }
    if ((word & 0xff100010) == 0xfe000010 or (word & 0x0f100010) == 0x0e000010) {
        return .send_word;
    }
    if ((word & 0xfff00000) == 0xfc400000 or (word & 0x0ff00000) == 0x0c400000) {
        return .send_pair;
    }
    if ((word & 0xff100010) == 0xfe100010 or (word & 0x0f100010) == 0x0e100010) {
        return .get_word;
    }
    if ((word & 0xfff00000) == 0xfc500000 or (word & 0x0ff00000) == 0x0c500000) {
        return .get_pair;
    }
    if ((word & 0xfe100000) == 0xfc000000 or (word & 0x0e100000) == 0x0c000000) {
        return .store;
    }
    return null;
}

pub fn runExternalArmHandler(state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (hooks.fallback) |callback| {
        callback(pc, state, hooks.context);
        return;
    }
    return error.UnknownInstruction;
}

pub fn runCoprocessor(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const op = coprocessorOp(word).?;
    const coproc = @intCast(usize, (word >> 8) & 0xf);
    if ((coproc & 0xe) == 0xa) {
        return error.UnknownInstruction;
    }
    const active = (word >> 28) == 0xf or state.conditionHolds(armCondition(word).?);
    if (!active) {
        state.write(.pc, pc + 4);
        return;
    }
    const hook = hooks.coprocessors[coproc] orelse return error.UnknownInstruction;
    switch (op) {
        .command => try runCoprocessorCommand(word, state, hook),
        .load => try runCoprocessorBlock(word, state, hook, pc, true),
        .send_word => try runCoprocessorSendWord(word, state, hook),
        .send_pair => try runCoprocessorSendPair(word, state, hook),
        .get_word => try runCoprocessorGetWord(word, state, hook),
        .get_pair => try runCoprocessorGetPair(word, state, hook),
        .store => try runCoprocessorBlock(word, state, hook, pc, false),
    }
    state.write(.pc, pc + 4);
}

pub fn runCoprocessorCommand(word: u32, state: *arm_state.MachineState, hook: arm_state.CoprocessorHooks) ArmStepError!void {
    const callback = hook.operate orelse return error.UnknownInstruction;
    callback(state, arm_state.CoprocessorCommand{
        .extended = (word >> 28) == 0xf,
        .op1 = @intCast(u4, (word >> 20) & 0xf),
        .dest = coprocessorReg(word >> 12),
        .base = coprocessorReg(word >> 16),
        .operand = coprocessorReg(word),
        .op2 = @intCast(u3, (word >> 5) & 0x7),
    }, hook.context);
}

pub fn runCoprocessorSendWord(word: u32, state: *arm_state.MachineState, hook: arm_state.CoprocessorHooks) ArmStepError!void {
    const source = armReg(word >> 12);
    if (source == .pc) {
        return error.Unpredictable;
    }
    const callback = hook.sendWord orelse return error.UnknownInstruction;
    callback(state, coprocessorWord(word), state.read(source), hook.context);
}

pub fn runCoprocessorSendPair(word: u32, state: *arm_state.MachineState, hook: arm_state.CoprocessorHooks) ArmStepError!void {
    const low = armReg(word >> 12);
    const high = armReg(word >> 16);
    if (low == .pc or high == .pc) {
        return error.Unpredictable;
    }
    const callback = hook.sendPair orelse return error.UnknownInstruction;
    callback(state, coprocessorPair(word), state.read(low), state.read(high), hook.context);
}

pub fn runCoprocessorGetWord(word: u32, state: *arm_state.MachineState, hook: arm_state.CoprocessorHooks) ArmStepError!void {
    const dest = armReg(word >> 12);
    const callback = hook.getWord orelse return error.UnknownInstruction;
    const value = callback(state, coprocessorWord(word), hook.context);
    if (dest == .pc) {
        state.cpsr = (state.cpsr & 0x0fffffff) | (value & 0xf0000000);
    } else {
        state.write(dest, value);
    }
}

pub fn runCoprocessorGetPair(word: u32, state: *arm_state.MachineState, hook: arm_state.CoprocessorHooks) ArmStepError!void {
    const low = armReg(word >> 12);
    const high = armReg(word >> 16);
    if (low == .pc or high == .pc or low == high) {
        return error.Unpredictable;
    }
    const callback = hook.getPair orelse return error.UnknownInstruction;
    const value = callback(state, coprocessorPair(word), hook.context);
    state.write(low, @intCast(u32, value & 0xffffffff));
    state.write(high, @intCast(u32, value >> 32));
}

pub fn runCoprocessorBlock(word: u32, state: *arm_state.MachineState, hook: arm_state.CoprocessorHooks, pc: u32, load: bool) ArmStepError!void {
    const pre = bits.getBit32(word, 24);
    const add = bits.getBit32(word, 23);
    const long = bits.getBit32(word, 22);
    const write_back = bits.getBit32(word, 21);
    if (!pre and !add and !long and !write_back) {
        return error.UnknownInstruction;
    }
    const base_reg = armReg(word >> 16);
    if (!load and base_reg == .pc and write_back) {
        return error.Unpredictable;
    }
    const offset = (word & 0xff) << 2;
    const base = readArmOperand(state, base_reg, pc);
    const offset_address = if (add) base +% offset else base -% offset;
    const address = if (pre) offset_address else base;
    const info = arm_state.CoprocessorBlock{
        .extended = (word >> 28) == 0xf,
        .long = long,
        .register = coprocessorReg(word >> 12),
        .option = if (!pre and !write_back and add) @intCast(u8, word & 0xff) else null,
    };
    if (load) {
        const callback = hook.loadBlock orelse return error.UnknownInstruction;
        callback(state, info, address, hook.context);
    } else {
        const callback = hook.storeBlock orelse return error.UnknownInstruction;
        callback(state, info, address, hook.context);
    }
    if (write_back) {
        state.write(base_reg, offset_address);
    }
}

pub fn coprocessorWord(word: u32) arm_state.CoprocessorWord {
    return arm_state.CoprocessorWord{
        .extended = (word >> 28) == 0xf,
        .op1 = @intCast(u3, (word >> 21) & 0x7),
        .base = coprocessorReg(word >> 16),
        .operand = coprocessorReg(word),
        .op2 = @intCast(u3, (word >> 5) & 0x7),
    };
}

pub fn coprocessorPair(word: u32) arm_state.CoprocessorPair {
    return arm_state.CoprocessorPair{
        .extended = (word >> 28) == 0xf,
        .op = @intCast(u4, (word >> 4) & 0xf),
        .operand = coprocessorReg(word),
    };
}
