const arm_state = @import("arm_state.zig");
const bits = @import("bits.zig");

pub const ArmStepError = error{
    UnknownInstruction,
    Unpredictable,
    MissingRead,
    MissingWrite,
};

pub const AddResult = struct {
    word: u32,
    carry: bool,
    overflow: bool,
};

pub const ShiftResult = struct {
    word: u32,
    carry: bool,
};

const ArmPattern = struct {
    mask: u32,
    expect: u32,
};

const external_arm_patterns = [_]ArmPattern{
    ArmPattern{ .mask = 0xfe000000, .expect = 0xfa000000 },
    ArmPattern{ .mask = 0x0ffffff0, .expect = 0x012fff30 },
    ArmPattern{ .mask = 0x0ffffff0, .expect = 0x012fff20 },
    ArmPattern{ .mask = 0xff000010, .expect = 0xfe000010 },
    ArmPattern{ .mask = 0x0f000010, .expect = 0x0e000000 },
    ArmPattern{ .mask = 0xfe100000, .expect = 0xfc100000 },
    ArmPattern{ .mask = 0x0e100000, .expect = 0x0c100000 },
    ArmPattern{ .mask = 0x0f100010, .expect = 0x0e000010 },
    ArmPattern{ .mask = 0xfff00000, .expect = 0xfc400000 },
    ArmPattern{ .mask = 0x0ff00000, .expect = 0x0c400000 },
    ArmPattern{ .mask = 0xff100010, .expect = 0xfe100010 },
    ArmPattern{ .mask = 0x0f100010, .expect = 0x0e100010 },
    ArmPattern{ .mask = 0xfff00000, .expect = 0xfc500000 },
    ArmPattern{ .mask = 0x0ff00000, .expect = 0x0c500000 },
    ArmPattern{ .mask = 0xfe100000, .expect = 0xfc000000 },
    ArmPattern{ .mask = 0x0e100000, .expect = 0x0c000000 },
    ArmPattern{ .mask = 0x0ff000f0, .expect = 0x01200070 },
    ArmPattern{ .mask = 0xfc70f000, .expect = 0xf450f000 },
    ArmPattern{ .mask = 0x0fffffff, .expect = 0x0320f004 },
    ArmPattern{ .mask = 0x0fffffff, .expect = 0x0320f002 },
    ArmPattern{ .mask = 0x0fffffff, .expect = 0x0320f003 },
    ArmPattern{ .mask = 0x0fffffff, .expect = 0x0320f001 },
    ArmPattern{ .mask = 0xffffffff, .expect = 0xf57ff01f },
    ArmPattern{ .mask = 0x0ff00fff, .expect = 0x01900f9f },
    ArmPattern{ .mask = 0x0ff00fff, .expect = 0x01d00f9f },
    ArmPattern{ .mask = 0x0ff00fff, .expect = 0x01b00f9f },
    ArmPattern{ .mask = 0x0ff00fff, .expect = 0x01f00f9f },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01800f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01c00f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01a00f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01e00f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01000090 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01400090 },
    ArmPattern{ .mask = 0x0f700000, .expect = 0x04700000 },
    ArmPattern{ .mask = 0x0f700010, .expect = 0x06700000 },
    ArmPattern{ .mask = 0x0f7000f0, .expect = 0x007000b0 },
    ArmPattern{ .mask = 0x0f700ff0, .expect = 0x003000b0 },
    ArmPattern{ .mask = 0x0e5000f0, .expect = 0x005000d0 },
    ArmPattern{ .mask = 0x0e500ff0, .expect = 0x001000d0 },
    ArmPattern{ .mask = 0x0f7000f0, .expect = 0x007000d0 },
    ArmPattern{ .mask = 0x0f700ff0, .expect = 0x003000d0 },
    ArmPattern{ .mask = 0x0e5000f0, .expect = 0x005000f0 },
    ArmPattern{ .mask = 0x0e500ff0, .expect = 0x001000f0 },
    ArmPattern{ .mask = 0x0f7000f0, .expect = 0x007000f0 },
    ArmPattern{ .mask = 0x0f700ff0, .expect = 0x003000f0 },
    ArmPattern{ .mask = 0x0f700000, .expect = 0x04300000 },
    ArmPattern{ .mask = 0x0f700010, .expect = 0x06300000 },
    ArmPattern{ .mask = 0x0f700000, .expect = 0x04600000 },
    ArmPattern{ .mask = 0x0f700010, .expect = 0x06600000 },
    ArmPattern{ .mask = 0x0f7000f0, .expect = 0x006000b0 },
    ArmPattern{ .mask = 0x0f700ff0, .expect = 0x002000b0 },
    ArmPattern{ .mask = 0x0f700000, .expect = 0x04200000 },
    ArmPattern{ .mask = 0x0f700010, .expect = 0x06200000 },
    ArmPattern{ .mask = 0x0e500000, .expect = 0x08100000 },
    ArmPattern{ .mask = 0x0e700000, .expect = 0x08500000 },
    ArmPattern{ .mask = 0x0e508000, .expect = 0x08508000 },
    ArmPattern{ .mask = 0x0e500000, .expect = 0x08000000 },
    ArmPattern{ .mask = 0x0e700000, .expect = 0x08400000 },
    ArmPattern{ .mask = 0x0fff0ff0, .expect = 0x016f0f10 },
    ArmPattern{ .mask = 0x0ffffff0, .expect = 0x0320f000 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06800fb0 },
    ArmPattern{ .mask = 0x0ff0f0f0, .expect = 0x0780f010 },
    ArmPattern{ .mask = 0x0ff000f0, .expect = 0x07800010 },
    ArmPattern{ .mask = 0x0ff00070, .expect = 0x06800010 },
    ArmPattern{ .mask = 0x0ff00070, .expect = 0x06800050 },
    ArmPattern{ .mask = 0x0fe00030, .expect = 0x06a00010 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06a00f30 },
    ArmPattern{ .mask = 0x0fe00030, .expect = 0x06e00010 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06e00f30 },
    ArmPattern{ .mask = 0x0ff00090, .expect = 0x01400080 },
    ArmPattern{ .mask = 0x0ff00090, .expect = 0x01000080 },
    ArmPattern{ .mask = 0x0ff0f090, .expect = 0x01600080 },
    ArmPattern{ .mask = 0x0ff000b0, .expect = 0x01200080 },
    ArmPattern{ .mask = 0x0ff0f0b0, .expect = 0x012000a0 },
    ArmPattern{ .mask = 0x0ff0f0d0, .expect = 0x0750f010 },
    ArmPattern{ .mask = 0x0ff000d0, .expect = 0x07500010 },
    ArmPattern{ .mask = 0x0ff000d0, .expect = 0x075000d0 },
    ArmPattern{ .mask = 0x0ff000d0, .expect = 0x07000010 },
    ArmPattern{ .mask = 0x0ff000d0, .expect = 0x07400010 },
    ArmPattern{ .mask = 0x0ff000d0, .expect = 0x07000050 },
    ArmPattern{ .mask = 0x0ff000d0, .expect = 0x07400050 },
    ArmPattern{ .mask = 0x0ff0f0d0, .expect = 0x0700f010 },
    ArmPattern{ .mask = 0x0ff0f0d0, .expect = 0x0700f050 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06100f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06100f10 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06100f30 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06100f50 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06100ff0 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06100f70 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06500f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06500f10 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06500f30 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06500f50 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06500ff0 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06500f70 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06200f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06200f10 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06200f30 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06200f50 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06200ff0 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06200f70 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06600f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06600f10 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06600f30 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06600f50 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06600ff0 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06600f70 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06300f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06300f10 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06300f30 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06300f50 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06300ff0 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06300f70 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06700f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06700f10 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06700f30 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06700f50 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06700ff0 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06700f70 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01000050 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01200050 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01400050 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01600050 },
    ArmPattern{ .mask = 0xfff1fe20, .expect = 0xf1000000 },
    ArmPattern{ .mask = 0xfffffdff, .expect = 0xf1010000 },
    ArmPattern{ .mask = 0x0fb00cff, .expect = 0x01000000 },
    ArmPattern{ .mask = 0x0db0f000, .expect = 0x0120f000 },
    ArmPattern{ .mask = 0x0fef0070, .expect = 0x01a00060 },
    ArmPattern{ .mask = 0xfe5ffff0, .expect = 0x06000010 },
};

const DataOp = enum(u4) {
    bit_and = 0x0,
    bit_xor = 0x1,
    sub = 0x2,
    reverse_sub = 0x3,
    add = 0x4,
    add_carry = 0x5,
    sub_carry = 0x6,
    reverse_sub_carry = 0x7,
    test_and = 0x8,
    test_xor = 0x9,
    compare = 0xa,
    compare_negative = 0xb,
    bit_or = 0xc,
    move = 0xd,
    bit_clear = 0xe,
    move_not = 0xf,
};

const ShiftMode = enum(u2) {
    left,
    right,
    signed_right,
    rotate_right,
};

const ExtendOp = enum(u4) {
    signed_byte_add,
    signed_half_add,
    signed_byte,
    signed_half,
    unsigned_byte_add,
    unsigned_half_add,
    unsigned_byte,
    unsigned_half,
};

const MultiplyOp = enum(u4) {
    multiply,
    multiply_add,
    unsigned_long,
    unsigned_long_add,
    unsigned_accumulate,
    signed_long,
    signed_long_add,
};

pub fn readArmWord(hooks: arm_state.HostHooks, pc: u32) ArmStepError!u32 {
    if (hooks.read32 == null) {
        return error.MissingRead;
    }
    return hooks.read32.?(pc & 0xfffffffc);
}

pub fn isSupervisorCall(word: u32) bool {
    return (word & 0x0f000000) == 0x0f000000 and armCondition(word) != null;
}

pub fn supervisorImmediate(word: u32) u32 {
    return word & 0x00ffffff;
}

pub fn isBranchImmediate(word: u32) bool {
    return (word & 0x0e000000) == 0x0a000000 and armCondition(word) != null;
}

pub fn isBranchExchange(word: u32) bool {
    return (word & 0x0ffffff0) == 0x012fff10 and armCondition(word) != null;
}

pub fn isMultiply(word: u32) bool {
    return multiplyOp(word) != null;
}

pub fn isLoadWord(word: u32) bool {
    if (armCondition(word) == null) {
        return false;
    }
    if ((word & 0x0e500000) == 0x04100000) {
        return true;
    }
    return (word & 0x0e500010) == 0x06100000;
}

pub fn isLoadByte(word: u32) bool {
    if (armCondition(word) == null) {
        return false;
    }
    if ((word & 0x0e500000) == 0x04500000) {
        return true;
    }
    return (word & 0x0e500010) == 0x06500000;
}

pub fn isLoadHalf(word: u32) bool {
    if (armCondition(word) == null) {
        return false;
    }
    if ((word & 0x0e5000f0) == 0x005000b0) {
        return true;
    }
    return (word & 0x0e500ff0) == 0x001000b0;
}

pub fn isLoadDouble(word: u32) bool {
    if (armCondition(word) == null) {
        return false;
    }
    if ((word & 0x0e5000f0) == 0x004000d0) {
        return true;
    }
    return (word & 0x0e500ff0) == 0x000000d0;
}

pub fn isStoreWord(word: u32) bool {
    if (armCondition(word) == null) {
        return false;
    }
    if ((word & 0x0e500000) == 0x04000000) {
        return true;
    }
    return (word & 0x0e500010) == 0x06000000;
}

pub fn isStoreByte(word: u32) bool {
    if (armCondition(word) == null) {
        return false;
    }
    if ((word & 0x0e500000) == 0x04400000) {
        return true;
    }
    return (word & 0x0e500010) == 0x06400000;
}

pub fn isStoreHalf(word: u32) bool {
    if (armCondition(word) == null) {
        return false;
    }
    if ((word & 0x0e5000f0) == 0x004000b0) {
        return true;
    }
    return (word & 0x0e500ff0) == 0x000000b0;
}

pub fn isStoreDouble(word: u32) bool {
    if (armCondition(word) == null) {
        return false;
    }
    if ((word & 0x0e5000f0) == 0x004000f0) {
        return true;
    }
    return (word & 0x0e500ff0) == 0x000000f0;
}

pub fn isDataProcessing(word: u32) bool {
    return dataOp(word) != null;
}

pub fn isAdcImmediate(word: u32) bool {
    return (word & 0x0fe00000) == 0x02a00000 and armCondition(word) != null;
}

pub fn isCmpImmediate(word: u32) bool {
    return (word & 0x0ff0f000) == 0x03500000 and armCondition(word) != null;
}

pub fn isRev(word: u32) bool {
    return (word & 0x0fff0ff0) == 0x06bf0f30 and armCondition(word) != null;
}

pub fn isRevHalfwords(word: u32) bool {
    return (word & 0x0fff0ff0) == 0x06bf0fb0 and armCondition(word) != null;
}

pub fn isRevSignedHalf(word: u32) bool {
    return (word & 0x0fff0ff0) == 0x06ff0fb0 and armCondition(word) != null;
}

pub fn expandArmImmediate(rotate: u8, value: u8) u32 {
    return rotateRightWord(@as(u32, value), rotate * 2);
}

pub fn runArmWord(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks) ArmStepError!void {
    const pc = state.read(.pc);
    if (isFloatAdd(word)) {
        return runFloatAdd(word, state, pc);
    }

    if (usesExternalArmHandler(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }

    if (isBranchImmediate(word)) {
        return runBranchImmediate(word, state, pc);
    }

    if (isBranchExchange(word)) {
        return runBranchExchange(word, state, pc);
    }

    if (isDataProcessing(word)) {
        return runDataProcessing(word, state, pc);
    }

    if (isMultiply(word)) {
        return runMultiply(word, state, pc);
    }

    if (isLoadWord(word)) {
        return runLoadWord(word, state, hooks, pc);
    }

    if (isLoadByte(word)) {
        return runLoadByte(word, state, hooks, pc);
    }

    if (isLoadHalf(word)) {
        return runLoadHalf(word, state, hooks, pc);
    }

    if (isLoadDouble(word)) {
        return runLoadDouble(word, state, hooks, pc);
    }

    if (isStoreWord(word)) {
        return runStoreWord(word, state, hooks, pc);
    }

    if (isStoreByte(word)) {
        return runStoreByte(word, state, hooks, pc);
    }

    if (isStoreHalf(word)) {
        return runStoreHalf(word, state, hooks, pc);
    }

    if (isStoreDouble(word)) {
        return runStoreDouble(word, state, hooks, pc);
    }

    if (isAdcImmediate(word)) {
        return runAdcImmediate(word, state, pc);
    }

    if (isCmpImmediate(word)) {
        return runCmpImmediate(word, state, pc);
    }

    if (isRev(word)) {
        return runRev(word, state, pc);
    }

    if (isRevHalfwords(word)) {
        return runRevHalfwords(word, state, pc);
    }

    if (isRevSignedHalf(word)) {
        return runRevSignedHalf(word, state, pc);
    }

    if (extendOp(word)) |_| {
        return runExtend(word, state, pc);
    }

    if (isSupervisorCall(word)) {
        const code = armCondition(word).?;
        if (!state.conditionHolds(code)) {
            state.write(.pc, pc + 4);
            return;
        }
        if (hooks.supervisor) |callback| {
            callback(supervisorImmediate(word), state);
            if (state.read(.pc) == pc) {
                state.write(.pc, pc + 4);
            }
            return;
        }
    }

    return runExternalArmHandler(state, hooks, pc);
}

pub fn runArmWithHooks(state: *arm_state.MachineState, hooks: arm_state.HostHooks) ArmStepError!void {
    const pc = state.read(.pc);
    const word = readArmWord(hooks, pc) catch |err| switch (err) {
        error.MissingRead => {
            if (hooks.fallback) |callback| {
                callback(pc, state);
                return;
            }
            return err;
        },
        else => return err,
    };
    return runArmWord(word, state, hooks);
}

fn armCondition(word: u32) ?arm_state.ConditionCode {
    return arm_state.conditionFromNibble(@intCast(u4, word >> 28));
}

fn usesExternalArmHandler(word: u32) bool {
    for (external_arm_patterns) |pattern| {
        if ((word & pattern.mask) == pattern.expect) {
            return true;
        }
    }
    return false;
}

fn runExternalArmHandler(state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (hooks.fallback) |callback| {
        callback(pc, state);
        return;
    }
    return error.UnknownInstruction;
}

fn isFloatAdd(word: u32) bool {
    return (word & 0x0fb00f50) == 0x0e300a00;
}

fn runFloatAdd(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        const left = readFloatPair(state, floatPairIndex(word >> 16, bits.getBit32(word, 7)));
        const right = readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
        const result = addFloat64(state, left, right);
        writeFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)), result);
    } else {
        const left = state.readFloatWord(floatWordIndex(word >> 16, bits.getBit32(word, 7)));
        const right = state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5)));
        const result = addFloat32(state, left, right);
        state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), result);
    }
    state.write(.pc, pc + 4);
}

fn addFloat32(state: *arm_state.MachineState, left: u32, right: u32) u32 {
    const left_word = floatInput32(state, left);
    const right_word = floatInput32(state, right);
    var result = @bitCast(u32, @bitCast(f32, left_word) + @bitCast(f32, right_word));
    result = floatOutput32(state, result);
    if (fpscrDefaultNaN(state.fpscr) and isNan32(result)) {
        return 0x7fc00000;
    }
    return result;
}

fn addFloat64(state: *arm_state.MachineState, left: u64, right: u64) u64 {
    const left_word = floatInput64(state, left);
    const right_word = floatInput64(state, right);
    var result = @bitCast(u64, @bitCast(f64, left_word) + @bitCast(f64, right_word));
    result = floatOutput64(state, result);
    if (fpscrDefaultNaN(state.fpscr) and isNan64(result)) {
        return 0x7ff8000000000000;
    }
    return result;
}

fn floatInput32(state: *arm_state.MachineState, value: u32) u32 {
    if (fpscrFlushZero(state.fpscr) and isDenormal32(value)) {
        state.fpscr |= 1 << 7;
        return 0;
    }
    return value;
}

fn floatInput64(state: *arm_state.MachineState, value: u64) u64 {
    if (fpscrFlushZero(state.fpscr) and isDenormal64(value)) {
        state.fpscr |= 1 << 7;
        return 0;
    }
    return value;
}

fn floatOutput32(state: *arm_state.MachineState, value: u32) u32 {
    if (fpscrFlushZero(state.fpscr) and isDenormal32(value)) {
        state.fpscr |= 1 << 3;
        return 0;
    }
    return value;
}

fn floatOutput64(state: *arm_state.MachineState, value: u64) u64 {
    if (fpscrFlushZero(state.fpscr) and isDenormal64(value)) {
        state.fpscr |= 1 << 3;
        return 0;
    }
    return value;
}

fn fpscrFlushZero(value: u32) bool {
    return bits.getBit32(value, 24);
}

fn fpscrDefaultNaN(value: u32) bool {
    return bits.getBit32(value, 25);
}

fn isDenormal32(value: u32) bool {
    const magnitude = value & 0x7fffffff;
    return magnitude != 0 and magnitude <= 0x007fffff;
}

fn isDenormal64(value: u64) bool {
    const magnitude = value & 0x7fffffffffffffff;
    return magnitude != 0 and magnitude <= 0x000fffffffffffff;
}

fn isNan32(value: u32) bool {
    return (value & 0x7fffffff) > 0x7f800000;
}

fn isNan64(value: u64) bool {
    return (value & 0x7fffffffffffffff) > 0x7ff0000000000000;
}

fn floatWordIndex(value: u32, high: bool) arm_state.FloatWordReg {
    const index = @intCast(u5, ((value & 0xf) << 1) | @as(u32, @boolToInt(high)));
    return @intToEnum(arm_state.FloatWordReg, index);
}

fn floatPairIndex(value: u32, high: bool) arm_state.FloatPairReg {
    const index = @intCast(u5, (value & 0xf) | (@as(u32, @boolToInt(high)) << 4));
    return @intToEnum(arm_state.FloatPairReg, index);
}

fn readFloatPair(state: *const arm_state.MachineState, reg: arm_state.FloatPairReg) u64 {
    return state.readFloatPair(reg);
}

fn writeFloatPair(state: *arm_state.MachineState, reg: arm_state.FloatPairReg, value: u64) void {
    state.writeFloatPair(reg, value);
}

fn runBranchImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn runBranchExchange(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const source = armReg(word);
    loadWritePc(state, readArmOperand(state, source, pc));
}

fn dataOp(word: u32) ?DataOp {
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

fn extendOp(word: u32) ?ExtendOp {
    if (armCondition(word) == null) {
        return null;
    }
    if ((word & 0x0fff03f0) == 0x06af0070) {
        return .signed_byte;
    }
    if ((word & 0x0fff03f0) == 0x06bf0070) {
        return .signed_half;
    }
    if ((word & 0x0fff03f0) == 0x06ef0070) {
        return .unsigned_byte;
    }
    if ((word & 0x0fff03f0) == 0x06ff0070) {
        return .unsigned_half;
    }
    if ((word & 0x0ff003f0) == 0x06a00070) {
        return .signed_byte_add;
    }
    if ((word & 0x0ff003f0) == 0x06b00070) {
        return .signed_half_add;
    }
    if ((word & 0x0ff003f0) == 0x06e00070) {
        return .unsigned_byte_add;
    }
    if ((word & 0x0ff003f0) == 0x06f00070) {
        return .unsigned_half_add;
    }
    return null;
}

fn multiplyOp(word: u32) ?MultiplyOp {
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

fn runDataProcessing(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const op = dataOp(word).?;
    try rejectBadRegisterShift(word, op);

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const set_flags = bits.getBit32(word, 20);
    const base = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const operand = dataOperand(word, state, pc);
    const left = readArmOperand(state, base, pc);

    switch (op) {
        .bit_and => try writeLogicalResult(state, pc, dest, left & operand.word, operand.carry, set_flags),
        .bit_xor => try writeLogicalResult(state, pc, dest, left ^ operand.word, operand.carry, set_flags),
        .sub => try writeMathResult(state, pc, dest, subWithCarry(left, operand.word, true), set_flags),
        .reverse_sub => try writeMathResult(state, pc, dest, subWithCarry(operand.word, left, true), set_flags),
        .add => try writeMathResult(state, pc, dest, addWithCarry(left, operand.word, false), set_flags),
        .add_carry => try writeMathResult(state, pc, dest, addWithCarry(left, operand.word, state.carry()), set_flags),
        .sub_carry => try writeMathResult(state, pc, dest, subWithCarry(left, operand.word, state.carry()), set_flags),
        .reverse_sub_carry => try writeMathResult(state, pc, dest, subWithCarry(operand.word, left, state.carry()), set_flags),
        .test_and => writeLogicalFlags(state, left & operand.word, operand.carry),
        .test_xor => writeLogicalFlags(state, left ^ operand.word, operand.carry),
        .compare => writeMathFlags(state, subWithCarry(left, operand.word, true)),
        .compare_negative => writeMathFlags(state, addWithCarry(left, operand.word, false)),
        .bit_or => try writeLogicalResult(state, pc, dest, left | operand.word, operand.carry, set_flags),
        .move => try writeLogicalResult(state, pc, dest, operand.word, operand.carry, set_flags),
        .bit_clear => try writeLogicalResult(state, pc, dest, left & ~operand.word, operand.carry, set_flags),
        .move_not => try writeLogicalResult(state, pc, dest, ~operand.word, operand.carry, set_flags),
    }

    switch (op) {
        .test_and, .test_xor, .compare, .compare_negative => state.write(.pc, pc + 4),
        else => {},
    }
}

fn runMultiply(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const op = multiplyOp(word).?;
    const code = armCondition(word).?;
    const set_flags = bits.getBit32(word, 20);
    const high = armReg(word >> 16);
    const low = armReg(word >> 12);
    const left = armReg(word);
    const right = armReg(word >> 8);

    if (high == .pc or left == .pc or right == .pc) {
        return error.Unpredictable;
    }
    switch (op) {
        .multiply_add => {},
        .multiply => {},
        else => {
            if (low == .pc or low == high) {
                return error.Unpredictable;
            }
        },
    }

    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    switch (op) {
        .multiply => {
            const result = state.read(left) *% state.read(right);
            state.write(high, result);
            if (set_flags) {
                writeMultiplyFlags(state, result);
            }
        },
        .multiply_add => {
            const addend = readArmOperand(state, low, pc);
            const result = (state.read(left) *% state.read(right)) +% addend;
            state.write(high, result);
            if (set_flags) {
                writeMultiplyFlags(state, result);
            }
        },
        .unsigned_long => {
            const result = @as(u64, state.read(left)) * @as(u64, state.read(right));
            writeLongResult(state, high, low, result);
            if (set_flags) {
                writeLongMultiplyFlags(state, result);
            }
        },
        .unsigned_long_add => {
            const result = (@as(u64, state.read(left)) * @as(u64, state.read(right))) +% readLong(state, high, low);
            writeLongResult(state, high, low, result);
            if (set_flags) {
                writeLongMultiplyFlags(state, result);
            }
        },
        .unsigned_accumulate => {
            const result = (@as(u64, state.read(left)) * @as(u64, state.read(right))) +% @as(u64, state.read(high)) +% @as(u64, state.read(low));
            writeLongResult(state, high, low, result);
        },
        .signed_long => {
            const result = signedProduct(state.read(left), state.read(right));
            writeLongResult(state, high, low, result);
            if (set_flags) {
                writeLongMultiplyFlags(state, result);
            }
        },
        .signed_long_add => {
            const result = signedProduct(state.read(left), state.read(right)) +% readLong(state, high, low);
            writeLongResult(state, high, low, result);
            if (set_flags) {
                writeLongMultiplyFlags(state, result);
            }
        },
    }
    state.write(.pc, pc + 4);
}

fn runExtend(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const op = extendOp(word).?;
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (dest == .pc or source == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const rotated = rotateRightWord(state.read(source), @intCast(u8, ((word >> 10) & 0x3) * 8));
    const base = readArmOperand(state, armReg(word >> 16), pc);
    const result = switch (op) {
        .signed_byte_add => base +% signExtendByte(rotated),
        .signed_half_add => base +% signExtendHalf(rotated),
        .signed_byte => signExtendByte(rotated),
        .signed_half => signExtendHalf(rotated),
        .unsigned_byte_add => base +% (rotated & 0xff),
        .unsigned_half_add => base +% (rotated & 0xffff),
        .unsigned_byte => rotated & 0xff,
        .unsigned_half => rotated & 0xffff,
    };
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

fn runLoadWord(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const pre_index = bits.getBit32(word, 24);
    const increase = bits.getBit32(word, 23);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const base_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
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

    const data = try readMemory32(state, hooks, address);
    if (dest == .pc) {
        loadWritePc(state, data);
        return;
    }
    state.write(dest, data);
    state.write(.pc, pc + 4);
}

fn runLoadByte(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const pre_index = bits.getBit32(word, 24);
    const increase = bits.getBit32(word, 23);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const base_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
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

    const data = try readMemory8(hooks, address);
    if (dest == .pc) {
        writeArmAluPc(state, data +% 4);
        return;
    }
    state.write(dest, data);
    state.write(.pc, pc + 4);
}

fn runLoadHalf(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const pre_index = bits.getBit32(word, 24);
    const increase = bits.getBit32(word, 23);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const base_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
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

    const data = try readMemory16(state, hooks, address);
    if (dest == .pc) {
        writeArmAluPc(state, @as(u32, data) +% 4);
        return;
    }
    state.write(dest, data);
    state.write(.pc, pc + 4);
}

fn runLoadDouble(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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
        if (base_reg == .pc) {
            return error.Unpredictable;
        }
        state.write(base_reg, changed);
    }

    var first = try readMemory32(state, hooks, address);
    var second = try readMemory32(state, hooks, address +% 4);
    if (first_reg == .pc) {
        first +%= 4;
    } else if (first_reg == .lr) {
        second +%= 4;
    }

    if (first_reg == .pc) {
        writeArmAluPc(state, first);
    } else {
        state.write(first_reg, first);
    }
    if (second_reg == .pc) {
        writeArmAluPc(state, second);
    } else {
        state.write(second_reg, second);
    }
    if (first_reg != .pc and second_reg != .pc) {
        state.write(.pc, pc + 4);
    }
}

fn runStoreWord(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runStoreByte(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runStoreHalf(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runStoreDouble(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn rejectBadRegisterShift(word: u32, op: DataOp) ArmStepError!void {
    if (bits.getBit32(word, 25) or !bits.getBit32(word, 4)) {
        return;
    }
    const base = armReg(word >> 16);
    const source = armReg(word);
    const amount = armReg(word >> 8);
    switch (op) {
        .compare, .compare_negative => return,
        .move, .move_not => {
            if (source == .pc or amount == .pc) {
                return error.Unpredictable;
            }
        },
        else => {
            if (base == .pc or source == .pc or amount == .pc) {
                return error.Unpredictable;
            }
        },
    }
}

fn transferWordOffset(word: u32, state: *const arm_state.MachineState, pc: u32) u32 {
    if (!bits.getBit32(word, 25)) {
        return word & 0xfff;
    }
    const source = armReg(word);
    const mode = @intToEnum(ShiftMode, @intCast(u2, (word >> 5) & 0x3));
    const amount = @intCast(u8, (word >> 7) & 0x1f);
    return shiftByImmediate(readArmOperand(state, source, pc), mode, amount, state.carry()).word;
}

fn offsetAddress(base: u32, offset: u32, increase: bool) u32 {
    if (increase) {
        return base +% offset;
    }
    return base -% offset;
}

fn transferHalfOffset(word: u32, state: *const arm_state.MachineState, pc: u32) u32 {
    if (bits.getBit32(word, 22)) {
        return ((word >> 4) & 0xf0) | (word & 0xf);
    }
    return readArmOperand(state, armReg(word), pc);
}

fn dataOperand(word: u32, state: *const arm_state.MachineState, pc: u32) ShiftResult {
    if (bits.getBit32(word, 25)) {
        const rotate = @intCast(u8, (word >> 8) & 0xf);
        const value = @intCast(u8, word & 0xff);
        const expanded = expandArmImmediate(rotate, value);
        return ShiftResult{
            .word = expanded,
            .carry = if (rotate == 0) state.carry() else bits.topBit(expanded),
        };
    }

    const source = armReg(word);
    const mode = @intToEnum(ShiftMode, @intCast(u2, (word >> 5) & 0x3));
    const value = readArmOperand(state, source, pc);
    if (bits.getBit32(word, 4)) {
        const amount_reg = armReg(word >> 8);
        const amount = @intCast(u8, readArmOperand(state, amount_reg, pc) & 0xff);
        return shiftByRegister(value, mode, amount, state.carry());
    }

    const amount = @intCast(u8, (word >> 7) & 0x1f);
    return shiftByImmediate(value, mode, amount, state.carry());
}

fn shiftByImmediate(value: u32, mode: ShiftMode, amount: u8, carry_in: bool) ShiftResult {
    return switch (mode) {
        .left => logicalLeft(value, amount, carry_in),
        .right => logicalRight(value, if (amount == 0) 32 else amount, carry_in),
        .signed_right => arithmeticRight(value, if (amount == 0) 32 else amount, carry_in),
        .rotate_right => if (amount == 0) carryRotate(value, carry_in) else rotateRight(value, amount, carry_in),
    };
}

fn shiftByRegister(value: u32, mode: ShiftMode, amount: u8, carry_in: bool) ShiftResult {
    return switch (mode) {
        .left => logicalLeft(value, amount, carry_in),
        .right => logicalRight(value, amount, carry_in),
        .signed_right => arithmeticRight(value, amount, carry_in),
        .rotate_right => rotateRight(value, amount, carry_in),
    };
}

fn carryRotate(value: u32, carry_in: bool) ShiftResult {
    const result = bits.rotateRightThroughCarry(value, carry_in);
    return ShiftResult{
        .word = result.word,
        .carry = result.carry,
    };
}

fn writeLogicalResult(state: *arm_state.MachineState, pc: u32, dest: arm_state.ArmReg, value: u32, carry: bool, set_flags: bool) ArmStepError!void {
    if (dest == .pc) {
        if (set_flags) {
            return error.Unpredictable;
        }
        writeArmAluPc(state, value);
        return;
    }
    state.write(dest, value);
    if (set_flags) {
        writeLogicalFlags(state, value, carry);
    }
    state.write(.pc, pc + 4);
}

fn writeMathResult(state: *arm_state.MachineState, pc: u32, dest: arm_state.ArmReg, result: AddResult, set_flags: bool) ArmStepError!void {
    if (dest == .pc) {
        if (set_flags) {
            return error.Unpredictable;
        }
        writeArmAluPc(state, result.word);
        return;
    }
    state.write(dest, result.word);
    if (set_flags) {
        writeMathFlags(state, result);
    }
    state.write(.pc, pc + 4);
}

fn writeLogicalFlags(state: *arm_state.MachineState, value: u32, carry: bool) void {
    state.setNegative(bits.topBit(value));
    state.setZero(value == 0);
    state.setCarry(carry);
}

fn writeMathFlags(state: *arm_state.MachineState, result: AddResult) void {
    state.setNegative(bits.topBit(result.word));
    state.setZero(result.word == 0);
    state.setCarry(result.carry);
    state.setOverflow(result.overflow);
}

fn writeMultiplyFlags(state: *arm_state.MachineState, value: u32) void {
    state.setNegative(bits.topBit(value));
    state.setZero(value == 0);
}

fn writeLongMultiplyFlags(state: *arm_state.MachineState, value: u64) void {
    state.setNegative((value & 0x8000000000000000) != 0);
    state.setZero(value == 0);
}

fn runAdcImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const set_flags = ((word >> 20) & 1) != 0;
    const base = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const rotate = @intCast(u8, (word >> 8) & 0xf);
    const imm = @intCast(u8, word & 0xff);
    const amount = expandArmImmediate(rotate, imm);
    const result = addWithCarry(readArmOperand(state, base, pc), amount, state.carry());

    if (dest == .pc) {
        if (set_flags) {
            return error.Unpredictable;
        }
        writeArmAluPc(state, result.word);
        return;
    }

    state.write(dest, result.word);
    if (set_flags) {
        state.setNegative((result.word & 0x80000000) != 0);
        state.setZero(result.word == 0);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
    }
    state.write(.pc, pc + 4);
}

fn runCmpImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const base = armReg(word >> 16);
    const rotate = @intCast(u8, (word >> 8) & 0xf);
    const imm = @intCast(u8, word & 0xff);
    const amount = expandArmImmediate(rotate, imm);
    const result = subWithCarry(readArmOperand(state, base, pc), amount, true);
    state.setNegative((result.word & 0x80000000) != 0);
    state.setZero(result.word == 0);
    state.setCarry(result.carry);
    state.setOverflow(result.overflow);
    state.write(.pc, pc + 4);
}

fn runRev(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (dest == .pc or source == .pc) {
        return error.Unpredictable;
    }
    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.write(dest, byteReverseWord(state.read(source)));
    }
    state.write(.pc, pc + 4);
}

fn runRevHalfwords(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (dest == .pc or source == .pc) {
        return error.Unpredictable;
    }
    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.write(dest, byteReverseHalfwords(state.read(source)));
    }
    state.write(.pc, pc + 4);
}

fn runRevSignedHalf(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (dest == .pc or source == .pc) {
        return error.Unpredictable;
    }
    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        state.write(dest, signExtendHalf(byteReverseHalf(state.read(source))));
    }
    state.write(.pc, pc + 4);
}

fn armReg(value: u32) arm_state.ArmReg {
    return @intToEnum(arm_state.ArmReg, @intCast(u8, value & 0xf));
}

fn nextArmReg(reg: arm_state.ArmReg) arm_state.ArmReg {
    const next = @enumToInt(reg) + 1;
    if (next >= 15) {
        return .pc;
    }
    return @intToEnum(arm_state.ArmReg, @intCast(u8, next));
}

fn readArmOperand(state: *const arm_state.MachineState, reg: arm_state.ArmReg, pc: u32) u32 {
    if (reg == .pc) {
        return pc + 8;
    }
    return state.read(reg);
}

fn writeArmAluPc(state: *arm_state.MachineState, value: u32) void {
    state.write(.pc, value & 0xfffffffc);
}

fn loadWritePc(state: *arm_state.MachineState, value: u32) void {
    if ((value & 1) != 0) {
        state.setThumb(true);
        state.write(.pc, value & 0xfffffffe);
    } else {
        state.setThumb(false);
        state.write(.pc, value & 0xfffffffc);
    }
}

fn readMemory32(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32) ArmStepError!u32 {
    const read32 = hooks.read32 orelse return error.MissingRead;
    var value = read32(address);
    if (state.bigEndian()) {
        value = byteReverseWord(value);
    }
    return value;
}

fn readMemory8(hooks: arm_state.HostHooks, address: u32) ArmStepError!u8 {
    const read8 = hooks.read8 orelse return error.MissingRead;
    return read8(address);
}

fn readMemory16(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32) ArmStepError!u16 {
    const read16 = hooks.read16 orelse return error.MissingRead;
    var value = read16(address);
    if (state.bigEndian()) {
        value = @intCast(u16, byteReverseHalf(value));
    }
    return value;
}

fn writeMemory32(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32, value: u32) ArmStepError!void {
    const write32 = hooks.write32 orelse return error.MissingWrite;
    var data = value;
    if (state.bigEndian()) {
        data = byteReverseWord(data);
    }
    write32(address, data);
}

fn writeMemory16(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32, value: u16) ArmStepError!void {
    const write16 = hooks.write16 orelse return error.MissingWrite;
    var data = value;
    if (state.bigEndian()) {
        data = @intCast(u16, byteReverseHalf(data));
    }
    write16(address, data);
}

fn writeMemory8(hooks: arm_state.HostHooks, address: u32, value: u8) ArmStepError!void {
    const write8 = hooks.write8 orelse return error.MissingWrite;
    write8(address, value);
}

fn addSigned(value: u32, offset: i32) u32 {
    if (offset < 0) {
        return value -% @intCast(u32, -offset);
    }
    return value +% @intCast(u32, offset);
}

fn readLong(state: *const arm_state.MachineState, high: arm_state.ArmReg, low: arm_state.ArmReg) u64 {
    return (@as(u64, state.read(high)) << 32) | @as(u64, state.read(low));
}

fn writeLongResult(state: *arm_state.MachineState, high: arm_state.ArmReg, low: arm_state.ArmReg, value: u64) void {
    state.write(low, @intCast(u32, value & 0xffffffff));
    state.write(high, @intCast(u32, value >> 32));
}

fn signedProduct(left: u32, right: u32) u64 {
    const wide_left = @as(i64, @bitCast(i32, left));
    const wide_right = @as(i64, @bitCast(i32, right));
    return @bitCast(u64, wide_left * wide_right);
}

fn rotateRightWord(value: u32, amount: u8) u32 {
    const shift = amount & 31;
    if (shift == 0) {
        return value;
    }
    return (value >> @intCast(u5, shift)) | (value << @intCast(u5, 32 - shift));
}

fn logicalLeft(value: u32, amount: u8, carry_in: bool) ShiftResult {
    if (amount == 0) {
        return ShiftResult{ .word = value, .carry = carry_in };
    }
    if (amount < 32) {
        return ShiftResult{
            .word = value << @intCast(u5, amount),
            .carry = bits.getBit32(value, @intCast(u5, 32 - amount)),
        };
    }
    if (amount == 32) {
        return ShiftResult{ .word = 0, .carry = bits.getBit32(value, 0) };
    }
    return ShiftResult{ .word = 0, .carry = false };
}

fn logicalRight(value: u32, amount: u8, carry_in: bool) ShiftResult {
    if (amount == 0) {
        return ShiftResult{ .word = value, .carry = carry_in };
    }
    if (amount < 32) {
        return ShiftResult{
            .word = value >> @intCast(u5, amount),
            .carry = bits.getBit32(value, @intCast(u5, amount - 1)),
        };
    }
    if (amount == 32) {
        return ShiftResult{ .word = 0, .carry = bits.getBit32(value, 31) };
    }
    return ShiftResult{ .word = 0, .carry = false };
}

fn arithmeticRight(value: u32, amount: u8, carry_in: bool) ShiftResult {
    if (amount == 0) {
        return ShiftResult{ .word = value, .carry = carry_in };
    }
    if (amount < 32) {
        const shift = @intCast(u5, amount);
        const fill = if (bits.topBit(value)) ~(@as(u32, 0xffffffff) >> shift) else @as(u32, 0);
        return ShiftResult{
            .word = (value >> shift) | fill,
            .carry = bits.getBit32(value, @intCast(u5, amount - 1)),
        };
    }
    if (bits.topBit(value)) {
        return ShiftResult{ .word = 0xffffffff, .carry = true };
    }
    return ShiftResult{ .word = 0, .carry = false };
}

fn rotateRight(value: u32, amount: u8, carry_in: bool) ShiftResult {
    if (amount == 0) {
        return ShiftResult{ .word = value, .carry = carry_in };
    }
    const shift = amount & 31;
    if (shift == 0) {
        return ShiftResult{ .word = value, .carry = bits.topBit(value) };
    }
    const word = (value >> @intCast(u5, shift)) | (value << @intCast(u5, 32 - shift));
    return ShiftResult{ .word = word, .carry = bits.topBit(word) };
}

fn byteReverseWord(value: u32) u32 {
    return ((value & 0x000000ff) << 24) |
        ((value & 0x0000ff00) << 8) |
        ((value & 0x00ff0000) >> 8) |
        ((value & 0xff000000) >> 24);
}

fn byteReverseHalf(value: u32) u32 {
    return ((value & 0xff) << 8) | ((value >> 8) & 0xff);
}

fn byteReverseHalfwords(value: u32) u32 {
    return ((value & 0x00ff00ff) << 8) | ((value & 0xff00ff00) >> 8);
}

fn signExtendByte(value: u32) u32 {
    const narrowed = value & 0xff;
    if ((narrowed & 0x80) != 0) {
        return narrowed | 0xffffff00;
    }
    return narrowed;
}

fn signExtendHalf(value: u32) u32 {
    const narrowed = value & 0xffff;
    if ((narrowed & 0x8000) != 0) {
        return narrowed | 0xffff0000;
    }
    return narrowed;
}

fn addWithCarry(left: u32, right: u32, carry_in: bool) AddResult {
    const carry: u64 = if (carry_in) 1 else 0;
    const wide = @as(u64, left) + @as(u64, right) + carry;
    const result = @intCast(u32, wide & 0xffffffff);
    const overflow = ((~(left ^ right) & (left ^ result)) & 0x80000000) != 0;
    return AddResult{
        .word = result,
        .carry = wide > 0xffffffff,
        .overflow = overflow,
    };
}

fn subWithCarry(left: u32, right: u32, carry_in: bool) AddResult {
    return addWithCarry(left, ~right, carry_in);
}
