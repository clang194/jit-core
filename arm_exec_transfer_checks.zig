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
usingnamespace @import("arm_exec_memory_run.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
usingnamespace @import("arm_exec_immediate_run.zig");
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");

pub fn rejectBadRegisterShift(word: u32, op: DataOp) ArmStepError!void {
    if (bits.getBit32(word, 25) or !bits.getBit32(word, 4)) {
        return;
    }
    const base = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const source = armReg(word);
    const amount = armReg(word >> 8);
    switch (op) {
        .test_and, .test_xor, .compare, .compare_negative => {
            if (base == .pc or source == .pc or amount == .pc) {
                return error.Unpredictable;
            }
        },
        .move, .move_not => {
            if (dest == .pc or source == .pc or amount == .pc) {
                return error.Unpredictable;
            }
        },
        else => {
            if (base == .pc or dest == .pc or source == .pc or amount == .pc) {
                return error.Unpredictable;
            }
        },
    }
}

pub fn isTransferUserMode(word: u32) bool {
    return !bits.getBit32(word, 24) and bits.getBit32(word, 21);
}

pub fn transferWritesBack(word: u32) bool {
    return !bits.getBit32(word, 24) or bits.getBit32(word, 21);
}

pub fn isWordTransferRegisterOffset(word: u32) bool {
    return bits.getBit32(word, 25);
}

pub fn isHalfTransferRegisterOffset(word: u32) bool {
    return !bits.getBit32(word, 22);
}

pub fn rejectWordLoad(word: u32) ArmStepError!void {
    const base = armReg(word >> 16);
    const dest = armReg(word >> 12);
    if (transferWritesBack(word)) {
        if (base == .pc or base == dest) {
            return error.Unpredictable;
        }
    }
    if (isWordTransferRegisterOffset(word) and armReg(word) == .pc) {
        return error.Unpredictable;
    }
}

pub fn rejectNarrowLoad(word: u32) ArmStepError!void {
    const base = armReg(word >> 16);
    const dest = armReg(word >> 12);
    if (dest == .pc) {
        return error.Unpredictable;
    }
    if (transferWritesBack(word)) {
        if (base == .pc or base == dest) {
            return error.Unpredictable;
        }
    }
    const register_offset = if ((word & 0x0e000000) == 0x06000000)
        isWordTransferRegisterOffset(word)
    else
        isHalfTransferRegisterOffset(word);
    if (register_offset and armReg(word) == .pc) {
        return error.Unpredictable;
    }
}

pub fn rejectDoubleLoad(word: u32) ArmStepError!void {
    const base = armReg(word >> 16);
    const first = armReg(word >> 12);
    const second = nextArmReg(first);
    if ((@enumToInt(first) & 1) != 0 or second == .pc) {
        return error.Unpredictable;
    }
    if (transferWritesBack(word)) {
        if (base == .pc or base == first or base == second) {
            return error.Unpredictable;
        }
    }
    if (isHalfTransferRegisterOffset(word)) {
        const offset = armReg(word);
        if (offset == .pc or offset == first or offset == second) {
            return error.Unpredictable;
        }
    }
}

pub fn rejectDoubleStore(word: u32) ArmStepError!void {
    const base = armReg(word >> 16);
    const first = armReg(word >> 12);
    const second = nextArmReg(first);
    if ((@enumToInt(first) & 1) != 0 or second == .pc) {
        return error.Unpredictable;
    }
    if (transferWritesBack(word)) {
        if (base == .pc or base == first or base == second) {
            return error.Unpredictable;
        }
    }
    if (isHalfTransferRegisterOffset(word) and armReg(word) == .pc) {
        return error.Unpredictable;
    }
}

pub fn rejectSingleStore(word: u32, reject_pc_source: bool, register_offset: bool) ArmStepError!void {
    const base = armReg(word >> 16);
    const source = armReg(word >> 12);
    if (reject_pc_source and source == .pc) {
        return error.Unpredictable;
    }
    if (bits.getBit32(word, 21)) {
        if (base == .pc or base == source) {
            return error.Unpredictable;
        }
    }
    if (register_offset and armReg(word) == .pc) {
        return error.Unpredictable;
    }
}

pub fn transferWordOffset(word: u32, state: *const arm_state.MachineState, pc: u32) u32 {
    if (!bits.getBit32(word, 25)) {
        return word & 0xfff;
    }
    const source = armReg(word);
    const mode = @intToEnum(ShiftMode, @intCast(u2, (word >> 5) & 0x3));
    const amount = @intCast(u8, (word >> 7) & 0x1f);
    return shiftByImmediate(readArmOperand(state, source, pc), mode, amount, state.carry()).word;
}

pub fn offsetAddress(base: u32, offset: u32, increase: bool) u32 {
    if (increase) {
        return base +% offset;
    }
    return base -% offset;
}

pub fn transferHalfOffset(word: u32, state: *const arm_state.MachineState, pc: u32) u32 {
    if (bits.getBit32(word, 22)) {
        return ((word >> 4) & 0xf0) | (word & 0xf);
    }
    return readArmOperand(state, armReg(word), pc);
}

