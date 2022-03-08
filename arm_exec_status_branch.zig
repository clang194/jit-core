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

pub fn runStatusRead(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    if (dest == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.write(dest, state.cpsr);
    }
    state.write(.pc, pc + 4);
}

pub fn runStatusWriteImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const mask = statusWriteMask(word);
    if (mask == 0) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const rotate = @intCast(u8, (word >> 8) & 0xf);
        const value = expandArmImmediate(rotate, @intCast(u8, word & 0xff));
        state.cpsr = mergeStatus(state.cpsr, value, mask);
    }
    state.write(.pc, pc + 4);
}

pub fn runStatusWriteRegister(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const source = armReg(word);
    if (source == .pc) {
        return error.Unpredictable;
    }

    const mask = statusWriteMask(word);
    if (mask == 0) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.cpsr = mergeStatus(state.cpsr, state.read(source), mask);
    }
    state.write(.pc, pc + 4);
}

pub fn runCountLeadingZeros(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (dest == .pc or source == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.write(dest, countLeadingZeros32(state.read(source)));
    }
    state.write(.pc, pc + 4);
}

pub fn runBranchImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const offset = bits.signExtend32((word & 0x00ffffff) << 2, 26) + 8;
    if (bits.getBit32(word, 24)) {
        state.write(.lr, pc + 4);
    }
    state.write(.pc, addSigned(pc, offset));
}

pub fn runBranchLinkExchangeImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const high = @as(u32, @boolToInt(bits.getBit32(word, 24)));
    const offset = bits.signExtend32(((word & 0x00ffffff) << 2) | (high << 1), 26) + 8;
    state.write(.lr, pc + 4);
    state.setThumb(true);
    state.write(.pc, addSigned(pc, offset) & 0xfffffffe);
}

pub fn runBranchExchange(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const source = armReg(word);
    loadWritePc(state, readArmOperand(state, source, pc));
}

pub fn runBranchExchangeRegister(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const source = armReg(word);
    if ((word & 0x0ffffff0) == 0x012fff30 and source == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const target = readArmOperand(state, source, pc);
    if ((word & 0x0ffffff0) == 0x012fff30) {
        state.write(.lr, pc + 4);
    }

    loadWritePc(state, target);
}

pub fn dataOp(word: u32) ?DataOp {
    if (armCondition(word) == null) {
        return null;
    }
    if ((word & 0x0c000000) != 0) {
        return null;
    }
    const immediate = bits.getBit32(word, 25);
    if (!immediate and bits.getBit32(word, 4) and bits.getBit32(word, 7)) {
        return null;
    }
    const op = @intToEnum(DataOp, @intCast(u4, (word >> 21) & 0xf));
    const set_flags = bits.getBit32(word, 20);
    const base = (word >> 16) & 0xf;
    const dest = (word >> 12) & 0xf;
    return switch (op) {
        .test_and, .test_xor, .compare, .compare_negative => if (set_flags and dest == 0) op else null,
        .move, .move_not => if (base == 0) op else null,
        else => op,
    };
}

pub fn extendOp(word: u32) ?ExtendOp {
    if (armCondition(word) == null) {
        return null;
    }
    if ((word & 0x0fff03f0) == 0x068f0070) {
        return .signed_byte_pair;
    }
    if ((word & 0x0fff03f0) == 0x06af0070) {
        return .signed_byte;
    }
    if ((word & 0x0fff03f0) == 0x06bf0070) {
        return .signed_half;
    }
    if ((word & 0x0fff03f0) == 0x06cf0070) {
        return .unsigned_byte_pair;
    }
    if ((word & 0x0fff03f0) == 0x06ef0070) {
        return .unsigned_byte;
    }
    if ((word & 0x0fff03f0) == 0x06ff0070) {
        return .unsigned_half;
    }
    if ((word & 0x0ff003f0) == 0x06800070) {
        return .signed_byte_pair_add;
    }
    if ((word & 0x0ff003f0) == 0x06a00070) {
        return .signed_byte_add;
    }
    if ((word & 0x0ff003f0) == 0x06b00070) {
        return .signed_half_add;
    }
    if ((word & 0x0ff003f0) == 0x06c00070) {
        return .unsigned_byte_pair_add;
    }
    if ((word & 0x0ff003f0) == 0x06e00070) {
        return .unsigned_byte_add;
    }
    if ((word & 0x0ff003f0) == 0x06f00070) {
        return .unsigned_half_add;
    }
    return null;
}

pub fn multiplyOp(word: u32) ?MultiplyOp {
    if (armCondition(word) == null) {
        return null;
    }
    if ((word & 0x0fe0f0f0) == 0x00000090) {
        return .multiply;
    }
    if ((word & 0x0fe000f0) == 0x00200090) {
        return .multiply_add;
    }
    if ((word & 0x0fe000f0) == 0x00800090) {
        return .unsigned_long;
    }
    if ((word & 0x0fe000f0) == 0x00a00090) {
        return .unsigned_long_add;
    }
    if ((word & 0x0ff000f0) == 0x00400090) {
        return .unsigned_accumulate;
    }
    if ((word & 0x0fe000f0) == 0x00c00090) {
        return .signed_long;
    }
    if ((word & 0x0fe000f0) == 0x00e00090) {
        return .signed_long_add;
    }
    return null;
}

