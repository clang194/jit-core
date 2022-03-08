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
