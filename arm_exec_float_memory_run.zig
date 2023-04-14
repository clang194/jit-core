const arm_state = @import("arm_state.zig");
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

pub fn runFloatLoad(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const offset = (word & 0xff) << 2;
    const base_reg = armReg(word >> 16);
    const base = if (base_reg == .pc) (pc + 8) & 0xfffffffc else state.read(base_reg);
    const address = if (bits.getBit32(word, 23)) base +% offset else base -% offset;

    if (bits.getBit32(word, 8)) {
        var low = try readMemory32(state, hooks, address);
        var high = try readMemory32(state, hooks, address +% 4);
        if (state.bigEndian()) {
            const saved = low;
            low = high;
            high = saved;
        }
        const value = @as(u64, low) | (@as(u64, high) << 32);
        writeFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)), value);
    } else {
        state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), try readMemory32(state, hooks, address));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatStore(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const offset = (word & 0xff) << 2;
    const base_reg = armReg(word >> 16);
    const base = if (base_reg == .pc) (pc + 8) & 0xfffffffc else state.read(base_reg);
    const address = if (bits.getBit32(word, 23)) base +% offset else base -% offset;

    if (bits.getBit32(word, 8)) {
        const value = readFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)));
        const low = @intCast(u32, value & 0xffffffff);
        const high = @intCast(u32, value >> 32);
        if (state.bigEndian()) {
            try writeMemory32(state, hooks, address, high);
            try writeMemory32(state, hooks, address +% 4, low);
        } else {
            try writeMemory32(state, hooks, address, low);
            try writeMemory32(state, hooks, address +% 4, high);
        }
    } else {
        try writeMemory32(state, hooks, address, state.readFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22))));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatPush(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const double = bits.getBit32(word, 8);
    const count = floatStackCount(word);
    const base = floatStackBase(word, double);
    if (count == 0 or base + count > 32 or (double and count > 16)) {
        return error.Unpredictable;
    }

    var address = state.read(.sp) -% ((word & 0xff) << 2);
    state.write(.sp, address);
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        if (double) {
            const value = readFloatPair(state, @intToEnum(arm_state.FloatPairReg, @intCast(u5, base + index)));
            const low = @intCast(u32, value & 0xffffffff);
            const high = @intCast(u32, value >> 32);
            if (state.bigEndian()) {
                try writeMemory32(state, hooks, address, high);
                try writeMemory32(state, hooks, address +% 4, low);
            } else {
                try writeMemory32(state, hooks, address, low);
                try writeMemory32(state, hooks, address +% 4, high);
            }
            address +%= 8;
        } else {
            try writeMemory32(state, hooks, address, state.readFloatWord(@intToEnum(arm_state.FloatWordReg, @intCast(u5, base + index))));
            address +%= 4;
        }
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatPop(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const double = bits.getBit32(word, 8);
    const count = floatStackCount(word);
    const base = floatStackBase(word, double);
    if (count == 0 or base + count > 32 or (double and count > 16)) {
        return error.Unpredictable;
    }

    var address = state.read(.sp);
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        if (double) {
            var low = try readMemory32(state, hooks, address);
            var high = try readMemory32(state, hooks, address +% 4);
            if (state.bigEndian()) {
                const saved = low;
                low = high;
                high = saved;
            }
            const value = @as(u64, low) | (@as(u64, high) << 32);
            writeFloatPair(state, @intToEnum(arm_state.FloatPairReg, @intCast(u5, base + index)), value);
            address +%= 8;
        } else {
            state.writeFloatWord(@intToEnum(arm_state.FloatWordReg, @intCast(u5, base + index)), try readMemory32(state, hooks, address));
            address +%= 4;
        }
    }
    state.write(.sp, address);
    state.write(.pc, pc + 4);
}

pub fn runFloatStoreMultiple(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const pre = bits.getBit32(word, 24);
    const up = bits.getBit32(word, 23);
    const writeback = bits.getBit32(word, 21);
    if ((!pre and !up and !writeback) or (pre and !writeback) or (pre == up and writeback)) {
        return error.UnknownInstruction;
    }

    const base_reg = armReg(word >> 16);
    if (base_reg == .pc and writeback) {
        return error.Unpredictable;
    }

    const double = bits.getBit32(word, 8);
    const count = floatStackCount(word);
    const base = floatStackBase(word, double);
    if (count == 0 or base + count > 32 or (double and count > 16)) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const offset = (word & 0xff) << 2;
    const start = if (up) readArmOperand(state, base_reg, pc) else readArmOperand(state, base_reg, pc) -% offset;
    var address = start;
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        if (double) {
            const value = readFloatPair(state, @intToEnum(arm_state.FloatPairReg, @intCast(u5, base + index)));
            const low = @intCast(u32, value & 0xffffffff);
            const high = @intCast(u32, value >> 32);
            if (state.bigEndian()) {
                try writeMemory32(state, hooks, address, high);
                try writeMemory32(state, hooks, address +% 4, low);
            } else {
                try writeMemory32(state, hooks, address, low);
                try writeMemory32(state, hooks, address +% 4, high);
            }
            address +%= 8;
        } else {
            try writeMemory32(state, hooks, address, state.readFloatWord(@intToEnum(arm_state.FloatWordReg, @intCast(u5, base + index))));
            address +%= 4;
        }
    }
    if (writeback) {
        state.write(base_reg, if (up) start +% offset else start);
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatLoadMultiple(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const pre = bits.getBit32(word, 24);
    const up = bits.getBit32(word, 23);
    const writeback = bits.getBit32(word, 21);
    if ((!pre and !up and !writeback) or (pre and !writeback) or (pre == up and writeback)) {
        return error.UnknownInstruction;
    }

    const base_reg = armReg(word >> 16);
    if (base_reg == .pc and writeback) {
        return error.Unpredictable;
    }

    const double = bits.getBit32(word, 8);
    const count = floatStackCount(word);
    const base = floatStackBase(word, double);
    if (count == 0 or base + count > 32 or (double and count > 16)) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const offset = (word & 0xff) << 2;
    const start = if (up) readArmOperand(state, base_reg, pc) else readArmOperand(state, base_reg, pc) -% offset;
    var address = start;
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        if (double) {
            var low = try readMemory32(state, hooks, address);
            var high = try readMemory32(state, hooks, address +% 4);
            if (state.bigEndian()) {
                const saved = low;
                low = high;
                high = saved;
            }
            const value = @as(u64, low) | (@as(u64, high) << 32);
            writeFloatPair(state, @intToEnum(arm_state.FloatPairReg, @intCast(u5, base + index)), value);
            address +%= 8;
        } else {
            state.writeFloatWord(@intToEnum(arm_state.FloatWordReg, @intCast(u5, base + index)), try readMemory32(state, hooks, address));
            address +%= 4;
        }
    }
    if (writeback) {
        state.write(base_reg, if (up) start +% offset else start);
    }
    state.write(.pc, pc + 4);
}
