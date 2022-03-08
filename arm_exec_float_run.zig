const arm_state = @import("arm_state.zig");
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

pub fn runFloatBinary(word: u32, state: *arm_state.MachineState, pc: u32, op: FloatBinaryOp) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        var dest = @as(u32, @enumToInt(floatPairIndex(word >> 12, bits.getBit32(word, 22))));
        var left_index = @as(u32, @enumToInt(floatPairIndex(word >> 16, bits.getBit32(word, 7))));
        var right_index = @as(u32, @enumToInt(floatPairIndex(word, bits.getBit32(word, 5))));
        const plan = try floatVectorPlan(state, true, dest, right_index);
        var index: u32 = 0;
        while (index < plan.count) : (index += 1) {
            const left = readFloatPairAt(state, left_index);
            const right = readFloatPairAt(state, right_index);
            const result = switch (op) {
                .add => addFloat64(state, left, right),
                .sub => subFloat64(state, left, right),
                .mul => mulFloat64(state, left, right),
                .neg_mul => negFloat64(mulFloat64(state, left, right)),
                .div => divFloat64(state, left, right),
            };
            writeFloatPairAt(state, dest, result);
            dest = advanceFloatIndex(dest, plan.stride, 4);
            left_index = advanceFloatIndex(left_index, plan.stride, 4);
            if (!plan.source_scalar) {
                right_index = advanceFloatIndex(right_index, plan.stride, 4);
            }
        }
    } else {
        var dest = @as(u32, @enumToInt(floatWordIndex(word >> 12, bits.getBit32(word, 22))));
        var left_index = @as(u32, @enumToInt(floatWordIndex(word >> 16, bits.getBit32(word, 7))));
        var right_index = @as(u32, @enumToInt(floatWordIndex(word, bits.getBit32(word, 5))));
        const plan = try floatVectorPlan(state, false, dest, right_index);
        var index: u32 = 0;
        while (index < plan.count) : (index += 1) {
            const left = readFloatWordAt(state, left_index);
            const right = readFloatWordAt(state, right_index);
            const result = switch (op) {
                .add => addFloat32(state, left, right),
                .sub => subFloat32(state, left, right),
                .mul => mulFloat32(state, left, right),
                .neg_mul => negFloat32(mulFloat32(state, left, right)),
                .div => divFloat32(state, left, right),
            };
            writeFloatWordAt(state, dest, result);
            dest = advanceFloatIndex(dest, plan.stride, 8);
            left_index = advanceFloatIndex(left_index, plan.stride, 8);
            if (!plan.source_scalar) {
                right_index = advanceFloatIndex(right_index, plan.stride, 8);
            }
        }
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatUnary(word: u32, state: *arm_state.MachineState, pc: u32, op: FloatUnaryOp) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        var dest = @as(u32, @enumToInt(floatPairIndex(word >> 12, bits.getBit32(word, 22))));
        var source_index = @as(u32, @enumToInt(floatPairIndex(word, bits.getBit32(word, 5))));
        const plan = try floatVectorPlan(state, true, dest, source_index);
        var index: u32 = 0;
        while (index < plan.count) : (index += 1) {
            const value = readFloatPairAt(state, source_index);
            const result = switch (op) {
                .move => value,
                .abs => value & 0x7fffffffffffffff,
                .neg => negFloat64(value),
                .sqrt => sqrtFloat64(state, value),
            };
            writeFloatPairAt(state, dest, result);
            dest = advanceFloatIndex(dest, plan.stride, 4);
            if (!plan.source_scalar) {
                source_index = advanceFloatIndex(source_index, plan.stride, 4);
            }
        }
    } else {
        var dest = @as(u32, @enumToInt(floatWordIndex(word >> 12, bits.getBit32(word, 22))));
        var source_index = @as(u32, @enumToInt(floatWordIndex(word, bits.getBit32(word, 5))));
        const plan = try floatVectorPlan(state, false, dest, source_index);
        var index: u32 = 0;
        while (index < plan.count) : (index += 1) {
            const value = readFloatWordAt(state, source_index);
            const result = switch (op) {
                .move => value,
                .abs => value & 0x7fffffff,
                .neg => negFloat32(value),
                .sqrt => sqrtFloat32(state, value),
            };
            writeFloatWordAt(state, dest, result);
            dest = advanceFloatIndex(dest, plan.stride, 8);
            if (!plan.source_scalar) {
                source_index = advanceFloatIndex(source_index, plan.stride, 8);
            }
        }
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatAdd(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatBinary(word, state, pc, .add);
}

pub fn runFloatMulAcc(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32, negate_acc: bool, negate_product: bool) ArmStepError!void {
    _ = hooks;

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        var dest = @as(u32, @enumToInt(floatPairIndex(word >> 12, bits.getBit32(word, 22))));
        var left_index = @as(u32, @enumToInt(floatPairIndex(word >> 16, bits.getBit32(word, 7))));
        var right_index = @as(u32, @enumToInt(floatPairIndex(word, bits.getBit32(word, 5))));
        const plan = try floatVectorPlan(state, true, dest, right_index);
        var index: u32 = 0;
        while (index < plan.count) : (index += 1) {
            var acc = readFloatPairAt(state, dest);
            const left = readFloatPairAt(state, left_index);
            const right = readFloatPairAt(state, right_index);
            var product = mulFloat64(state, left, right);
            if (negate_acc) {
                acc = negFloat64(acc);
            }
            if (negate_product) {
                product = negFloat64(product);
            }
            writeFloatPairAt(state, dest, addFloat64(state, acc, product));
            dest = advanceFloatIndex(dest, plan.stride, 4);
            left_index = advanceFloatIndex(left_index, plan.stride, 4);
            if (!plan.source_scalar) {
                right_index = advanceFloatIndex(right_index, plan.stride, 4);
            }
        }
    } else {
        var dest = @as(u32, @enumToInt(floatWordIndex(word >> 12, bits.getBit32(word, 22))));
        var left_index = @as(u32, @enumToInt(floatWordIndex(word >> 16, bits.getBit32(word, 7))));
        var right_index = @as(u32, @enumToInt(floatWordIndex(word, bits.getBit32(word, 5))));
        const plan = try floatVectorPlan(state, false, dest, right_index);
        var index: u32 = 0;
        while (index < plan.count) : (index += 1) {
            var acc = readFloatWordAt(state, dest);
            const left = readFloatWordAt(state, left_index);
            const right = readFloatWordAt(state, right_index);
            var product = mulFloat32(state, left, right);
            if (negate_acc) {
                acc = negFloat32(acc);
            }
            if (negate_product) {
                product = negFloat32(product);
            }
            writeFloatWordAt(state, dest, addFloat32(state, acc, product));
            dest = advanceFloatIndex(dest, plan.stride, 8);
            left_index = advanceFloatIndex(left_index, plan.stride, 8);
            if (!plan.source_scalar) {
                right_index = advanceFloatIndex(right_index, plan.stride, 8);
            }
        }
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatSub(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatBinary(word, state, pc, .sub);
}

pub fn runFloatMul(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatBinary(word, state, pc, .mul);
}

pub fn runFloatNegMul(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatBinary(word, state, pc, .neg_mul);
}

pub fn runFloatDiv(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatBinary(word, state, pc, .div);
}

pub fn runFloatMoveCoreToPairLow(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const core = armReg(word >> 12);
    if (core == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const pair = floatPairIndex(word >> 16, bits.getBit32(word, 7));
        const value = readFloatPair(state, pair) & 0xffffffff00000000;
        writeFloatPair(state, pair, value | @as(u64, state.read(core)));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMovePairLowToCore(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const core = armReg(word >> 12);
    if (core == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const value = readFloatPair(state, floatPairIndex(word >> 16, bits.getBit32(word, 7)));
        state.write(core, @intCast(u32, value & 0xffffffff));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMoveCoreToWord(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const core = armReg(word >> 12);
    if (core == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.writeFloatWord(floatWordIndex(word >> 16, bits.getBit32(word, 7)), state.read(core));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMoveWordToCore(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const core = armReg(word >> 12);
    if (core == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.write(core, state.readFloatWord(floatWordIndex(word >> 16, bits.getBit32(word, 7))));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMoveTwoCoreToTwoWord(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const second = armReg(word >> 16);
    const first = armReg(word >> 12);
    const dest = floatWordIndex(word, bits.getBit32(word, 5));
    if (first == .pc or second == .pc or isLastFloatWord(dest)) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.writeFloatWord(dest, state.read(first));
        state.writeFloatWord(nextFloatWordReg(dest), state.read(second));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMoveTwoWordToTwoCore(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const second = armReg(word >> 16);
    const first = armReg(word >> 12);
    const source = floatWordIndex(word, bits.getBit32(word, 5));
    if (first == .pc or second == .pc or first == second or isLastFloatWord(source)) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.write(first, state.readFloatWord(source));
        state.write(second, state.readFloatWord(nextFloatWordReg(source)));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMoveTwoCoreToPair(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const second = armReg(word >> 16);
    const first = armReg(word >> 12);
    if (first == .pc or second == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const value = @as(u64, state.read(first)) | (@as(u64, state.read(second)) << 32);
        writeFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)), value);
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMovePairToTwoCore(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const second = armReg(word >> 16);
    const first = armReg(word >> 12);
    if (first == .pc or second == .pc or first == second) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const value = readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
        state.write(first, @intCast(u32, value & 0xffffffff));
        state.write(second, @intCast(u32, value >> 32));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatMoveReg(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatUnary(word, state, pc, .move);
}

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

pub fn runFloatAbs(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatUnary(word, state, pc, .abs);
}

pub fn runFloatNeg(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatUnary(word, state, pc, .neg);
}

pub fn runFloatSqrt(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    _ = hooks;
    return runFloatUnary(word, state, pc, .sqrt);
}

pub fn runFloatConvertWidth(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        if (bits.getBit32(word, 8)) {
            const value = readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
            state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), convertFloat64To32(state, value));
        } else {
            const value = state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5)));
            writeFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)), convertFloat32To64(state, value));
        }
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatConvertIntToFloat(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const raw = state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5)));
        if (bits.getBit32(word, 8)) {
            const value = if (bits.getBit32(word, 7)) floatFromSigned32To64(state, raw) else floatFromUnsigned32To64(state, raw);
            writeFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)), value);
        } else {
            const value = if (bits.getBit32(word, 7)) floatFromSigned32To32(state, raw) else floatFromUnsigned32To32(state, raw);
            state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), value);
        }
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatConvertToUnsigned(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const value = if (bits.getBit32(word, 8))
            convertFloat64ToUnsigned32(state, readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5))), bits.getBit32(word, 7))
        else
            convertFloat32ToUnsigned32(state, state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5))), bits.getBit32(word, 7));
        state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), value);
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatConvertToSigned(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const value = if (bits.getBit32(word, 8))
            convertFloat64ToSigned32(state, readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5))), bits.getBit32(word, 7))
        else
            convertFloat32ToSigned32(state, state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5))), bits.getBit32(word, 7));
        state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), value);
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatCompare(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const double = bits.getBit32(word, 8);
        const zero = (word & 0x0fbf0e7f) == 0x0eb50a40;
        const invalid_on_quiet = bits.getBit32(word, 7);
        if (double) {
            const left = readFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)));
            const right = if (zero) @as(u64, 0) else readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
            writeFloatCompare64(state, left, right, invalid_on_quiet);
        } else {
            const left = state.readFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)));
            const right = if (zero) @as(u32, 0) else state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5)));
            writeFloatCompare32(state, left, right, invalid_on_quiet);
        }
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatStatusWrite(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const source = armReg(word >> 12);
    if (source == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.writeFloatStatus(state.read(source));
    }
    state.write(.pc, pc + 4);
}

pub fn runFloatStatusRead(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        if (dest == .pc) {
            state.cpsr = mergeStatus(state.cpsr, state.readFloatStatus(), 0xf0000000);
        } else {
            state.write(dest, state.readFloatStatus());
        }
    }
    state.write(.pc, pc + 4);
}

