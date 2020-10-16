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

const HalfMultiplyOp = enum(u3) {
    long_add,
    add,
    multiply,
    word_add,
    word_multiply,
};

const DualMultiplyOp = enum(u3) {
    add,
    long_add,
    sub,
    long_sub,
    pair_add,
    pair_sub,
};

pub fn readArmWord(hooks: arm_state.HostHooks, pc: u32) ArmStepError!u32 {
    const address = pc & 0xfffffffc;
    if (hooks.readDirect32(address)) |value| {
        return value;
    }
    const read32 = hooks.read32 orelse return error.MissingRead;
    return read32(address);
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

fn isBranchExchangeRegister(word: u32) bool {
    return ((word & 0x0ffffff0) == 0x012fff10 or
        (word & 0x0ffffff0) == 0x012fff20 or
        (word & 0x0ffffff0) == 0x012fff30) and armCondition(word) != null;
}

fn isBranchLinkExchangeImmediate(word: u32) bool {
    return (word & 0xfe000000) == 0xfa000000;
}

fn isClearExclusive(word: u32) bool {
    return word == 0xf57ff01f;
}

fn isLoadExclusive(word: u32) bool {
    return ((word & 0x0ff00fff) == 0x01900f9f or
        (word & 0x0ff00fff) == 0x01d00f9f or
        (word & 0x0ff00fff) == 0x01b00f9f or
        (word & 0x0ff00fff) == 0x01f00f9f) and armCondition(word) != null;
}

fn isStoreExclusive(word: u32) bool {
    return ((word & 0x0ff00ff0) == 0x01800f90 or
        (word & 0x0ff00ff0) == 0x01c00f90 or
        (word & 0x0ff00ff0) == 0x01a00f90 or
        (word & 0x0ff00ff0) == 0x01e00f90) and armCondition(word) != null;
}

fn isSwap(word: u32) bool {
    return ((word & 0x0ff00ff0) == 0x01000090 or
        (word & 0x0ff00ff0) == 0x01400090) and armCondition(word) != null;
}

fn isEndianSelect(word: u32) bool {
    return (word & 0xfffffdff) == 0xf1010000;
}

fn isStatusRead(word: u32) bool {
    return (word & 0x0fff0fff) == 0x010f0000 and armCondition(word) != null;
}

fn isStatusWriteImmediate(word: u32) bool {
    return (word & 0x0ff3f000) == 0x0320f000 and armCondition(word) != null;
}

fn isStatusWriteRegister(word: u32) bool {
    return (word & 0x0ff3fff0) == 0x0120f000 and armCondition(word) != null;
}

fn isUnsignedSaturatingSubBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06600ff0 and armCondition(word) != null;
}

fn isSignedSaturatingSubBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06200ff0 and armCondition(word) != null;
}

fn isUnsignedSaturatingAddBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06600f90 and armCondition(word) != null;
}

fn isSignedSaturatingAddBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06200f90 and armCondition(word) != null;
}

fn isUnsignedSaturatingSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06600f70 and armCondition(word) != null;
}

fn isSignedSaturatingSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06200f70 and armCondition(word) != null;
}

fn isUnsignedSaturatingAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06600f10 and armCondition(word) != null;
}

fn isSignedSaturatingAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06200f10 and armCondition(word) != null;
}

pub fn isMultiply(word: u32) bool {
    return multiplyOp(word) != null;
}

fn isLoadMultiple(word: u32) bool {
    return (word & 0x0e500000) == 0x08100000 and armCondition(word) != null;
}

fn isStoreMultiple(word: u32) bool {
    return (word & 0x0e500000) == 0x08000000 and armCondition(word) != null;
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

pub fn isLoadSignedByte(word: u32) bool {
    if (armCondition(word) == null) {
        return false;
    }
    if ((word & 0x0e5000f0) == 0x005000d0) {
        return true;
    }
    return (word & 0x0e500ff0) == 0x001000d0;
}

pub fn isLoadSignedHalf(word: u32) bool {
    if (armCondition(word) == null) {
        return false;
    }
    if ((word & 0x0e5000f0) == 0x005000f0) {
        return true;
    }
    return (word & 0x0e500ff0) == 0x001000f0;
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
        return runFloatAdd(word, state, hooks, pc);
    }

    if (isFloatMulAdd(word)) {
        return runFloatMulAcc(word, state, hooks, pc, false, false);
    }

    if (isFloatMulSub(word)) {
        return runFloatMulAcc(word, state, hooks, pc, false, true);
    }

    if (isFloatNegMulAdd(word)) {
        return runFloatMulAcc(word, state, hooks, pc, true, true);
    }

    if (isFloatNegMulSub(word)) {
        return runFloatMulAcc(word, state, hooks, pc, true, false);
    }

    if (isFloatSub(word)) {
        return runFloatSub(word, state, hooks, pc);
    }

    if (isFloatMul(word)) {
        return runFloatMul(word, state, hooks, pc);
    }

    if (isFloatNegMul(word)) {
        return runFloatNegMul(word, state, hooks, pc);
    }

    if (isFloatDiv(word)) {
        return runFloatDiv(word, state, hooks, pc);
    }

    if (isFloatMoveCoreToPairLow(word)) {
        return runFloatMoveCoreToPairLow(word, state, pc);
    }

    if (isFloatMovePairLowToCore(word)) {
        return runFloatMovePairLowToCore(word, state, pc);
    }

    if (isFloatMoveCoreToWord(word)) {
        return runFloatMoveCoreToWord(word, state, pc);
    }

    if (isFloatMoveWordToCore(word)) {
        return runFloatMoveWordToCore(word, state, pc);
    }

    if (isFloatMoveTwoCoreToTwoWord(word)) {
        return runFloatMoveTwoCoreToTwoWord(word, state, pc);
    }

    if (isFloatMoveTwoWordToTwoCore(word)) {
        return runFloatMoveTwoWordToTwoCore(word, state, pc);
    }

    if (isFloatMoveTwoCoreToPair(word)) {
        return runFloatMoveTwoCoreToPair(word, state, pc);
    }

    if (isFloatMovePairToTwoCore(word)) {
        return runFloatMovePairToTwoCore(word, state, pc);
    }

    if (isFloatMoveReg(word)) {
        return runFloatMoveReg(word, state, hooks, pc);
    }

    if (isFloatLoad(word)) {
        return runFloatLoad(word, state, hooks, pc);
    }

    if (isFloatStore(word)) {
        return runFloatStore(word, state, hooks, pc);
    }

    if (isFloatPush(word)) {
        return runFloatPush(word, state, hooks, pc);
    }

    if (isFloatStoreMultiple(word)) {
        return runFloatStoreMultiple(word, state, hooks, pc);
    }

    if (isFloatPop(word)) {
        return runFloatPop(word, state, hooks, pc);
    }

    if (isFloatLoadMultiple(word)) {
        return runFloatLoadMultiple(word, state, hooks, pc);
    }

    if (isFloatAbs(word)) {
        return runFloatAbs(word, state, hooks, pc);
    }

    if (isFloatNeg(word)) {
        return runFloatNeg(word, state, hooks, pc);
    }

    if (isFloatSqrt(word)) {
        return runFloatSqrt(word, state, hooks, pc);
    }

    if (isFloatConvertWidth(word)) {
        return runFloatConvertWidth(word, state, hooks, pc);
    }

    if (isFloatConvertIntToFloat(word)) {
        return runFloatConvertIntToFloat(word, state, hooks, pc);
    }

    if (isFloatConvertToUnsigned(word)) {
        return runFloatConvertToUnsigned(word, state, hooks, pc);
    }

    if (isFloatConvertToSigned(word)) {
        return runFloatConvertToSigned(word, state, hooks, pc);
    }

    if (isFloatStatusWrite(word)) {
        return runFloatStatusWrite(word, state, pc);
    }

    if (isFloatStatusRead(word)) {
        return runFloatStatusRead(word, state, pc);
    }

    if (isSignedTopMultiply(word)) {
        return runSignedTopMultiply(word, state, pc);
    }

    if (halfMultiplyOp(word) != null) {
        return runHalfMultiply(word, state, pc);
    }

    if (dualMultiplyOp(word) != null) {
        return runDualMultiply(word, state, pc);
    }

    if (isHintNoOp(word)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (isArmNoOp(word)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (isBranchLinkExchangeImmediate(word)) {
        return runBranchLinkExchangeImmediate(word, state, pc);
    }

    if (isBranchExchangeRegister(word)) {
        return runBranchExchangeRegister(word, state, pc);
    }

    if (isClearExclusive(word)) {
        state.exclusive = false;
        state.write(.pc, pc + 4);
        return;
    }

    if (isLoadExclusive(word)) {
        return runLoadExclusive(word, state, hooks, pc);
    }

    if (isStoreExclusive(word)) {
        return runStoreExclusive(word, state, hooks, pc);
    }

    if (isSwap(word)) {
        return runSwap(word, state, hooks, pc);
    }

    if (isEndianSelect(word)) {
        state.setBigEndian((word & 0x00000200) != 0);
        state.write(.pc, pc + 4);
        return;
    }

    if (isStatusRead(word)) {
        return runStatusRead(word, state, pc);
    }

    if (isStatusWriteImmediate(word)) {
        return runStatusWriteImmediate(word, state, pc);
    }

    if (isStatusWriteRegister(word)) {
        return runStatusWriteRegister(word, state, pc);
    }

    if (isUnsignedSaturatingSubBytes(word)) {
        return runUnsignedSaturatingSubBytes(word, state, pc);
    }

    if (isSignedSaturatingSubBytes(word)) {
        return runSignedSaturatingSubBytes(word, state, pc);
    }

    if (isUnsignedSaturatingAddBytes(word)) {
        return runUnsignedSaturatingAddBytes(word, state, pc);
    }

    if (isSignedSaturatingAddBytes(word)) {
        return runSignedSaturatingAddBytes(word, state, pc);
    }

    if (isUnsignedSaturatingSubHalves(word)) {
        return runUnsignedSaturatingSubHalves(word, state, pc);
    }

    if (isSignedSaturatingSubHalves(word)) {
        return runSignedSaturatingSubHalves(word, state, pc);
    }

    if (isUnsignedSaturatingAddHalves(word)) {
        return runUnsignedSaturatingAddHalves(word, state, pc);
    }

    if (isSignedSaturatingAddHalves(word)) {
        return runSignedSaturatingAddHalves(word, state, pc);
    }

    if (isLoadMultiple(word)) {
        return runLoadMultiple(word, state, hooks, pc);
    }

    if (isStoreMultiple(word)) {
        return runStoreMultiple(word, state, hooks, pc);
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

    if (isLoadSignedByte(word)) {
        return runLoadSignedByte(word, state, hooks, pc);
    }

    if (isLoadSignedHalf(word)) {
        return runLoadSignedHalf(word, state, hooks, pc);
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
            state.write(.pc, pc + 4);
            callback(supervisorImmediate(word), state);
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
                callback(pc, state, hooks.context);
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
        callback(pc, state, hooks.context);
        return;
    }
    return error.UnknownInstruction;
}

fn isHintNoOp(word: u32) bool {
    return (word & 0xfd70f000) == 0xf550f000 or
        (word & 0x0fffffff) == 0x0320f004 or
        (word & 0x0fffffff) == 0x0320f002 or
        (word & 0x0fffffff) == 0x0320f003 or
        (word & 0x0fffffff) == 0x0320f001;
}

fn isArmNoOp(word: u32) bool {
    return (word & 0x0fffffff) == 0x0320f000;
}

fn isFloatAdd(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e300a00;
}

fn isFloatMulAdd(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e000a00;
}

fn isFloatMulSub(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e000a40;
}

fn isFloatNegMulSub(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e100a00;
}

fn isFloatNegMulAdd(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e100a40;
}

fn isFloatSub(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e300a40;
}

fn isFloatMul(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e200a00;
}

fn isFloatNegMul(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e200a40;
}

fn isFloatDiv(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e800a00;
}

fn isFloatMoveCoreToPairLow(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00f7f) == 0x0e000b10;
}

fn isFloatMovePairLowToCore(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00f7f) == 0x0e100b10;
}

fn isFloatMoveCoreToWord(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00f7f) == 0x0e000a10;
}

fn isFloatMoveWordToCore(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00f7f) == 0x0e100a10;
}

fn isFloatMoveTwoCoreToTwoWord(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00fd0) == 0x0c400a10;
}

fn isFloatMoveTwoWordToTwoCore(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00fd0) == 0x0c500a10;
}

fn isFloatMoveTwoCoreToPair(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00fd0) == 0x0c400b10;
}

fn isFloatMovePairToTwoCore(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00fd0) == 0x0c500b10;
}

fn isFloatMoveReg(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0ed0) == 0x0eb00a40;
}

fn isFloatLoad(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0f300e00) == 0x0d100a00;
}

fn isFloatStore(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0f300e00) == 0x0d000a00;
}

fn isFloatPush(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0e00) == 0x0d2d0a00;
}

fn isFloatStoreMultiple(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0e100e00) == 0x0c000a00;
}

fn isFloatPop(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0e00) == 0x0cbd0a00;
}

fn isFloatLoadMultiple(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0e100e00) == 0x0c100a00;
}

fn isFloatAbs(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0ed0) == 0x0eb00ac0;
}

fn isFloatNeg(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0ed0) == 0x0eb10a40;
}

fn isFloatSqrt(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0ed0) == 0x0eb10ac0;
}

fn isFloatConvertWidth(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0ed0) == 0x0eb70ac0;
}

fn isFloatConvertIntToFloat(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0e50) == 0x0eb80a40;
}

fn isFloatConvertToUnsigned(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0e50) == 0x0ebc0a40;
}

fn isFloatConvertToSigned(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0e50) == 0x0ebd0a40;
}

fn isFloatStatusWrite(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fff0fff) == 0x0ee10a10;
}

fn isFloatStatusRead(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fff0fff) == 0x0ef10a10;
}

fn isVfpCondition(word: u32) bool {
    return (word >> 28) != 0xf;
}

fn runFloatAdd(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

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

fn runFloatMulAcc(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32, negate_acc: bool, negate_product: bool) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        var acc = readFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)));
        const left = readFloatPair(state, floatPairIndex(word >> 16, bits.getBit32(word, 7)));
        const right = readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
        var product = mulFloat64(state, left, right);
        if (negate_acc) {
            acc = negFloat64(acc);
        }
        if (negate_product) {
            product = negFloat64(product);
        }
        const result = addFloat64(state, acc, product);
        writeFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)), result);
    } else {
        var acc = state.readFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)));
        const left = state.readFloatWord(floatWordIndex(word >> 16, bits.getBit32(word, 7)));
        const right = state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5)));
        var product = mulFloat32(state, left, right);
        if (negate_acc) {
            acc = negFloat32(acc);
        }
        if (negate_product) {
            product = negFloat32(product);
        }
        const result = addFloat32(state, acc, product);
        state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), result);
    }
    state.write(.pc, pc + 4);
}

fn runFloatSub(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        const left = readFloatPair(state, floatPairIndex(word >> 16, bits.getBit32(word, 7)));
        const right = readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
        const result = subFloat64(state, left, right);
        writeFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)), result);
    } else {
        const left = state.readFloatWord(floatWordIndex(word >> 16, bits.getBit32(word, 7)));
        const right = state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5)));
        const result = subFloat32(state, left, right);
        state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), result);
    }
    state.write(.pc, pc + 4);
}

fn runFloatMul(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        const left = readFloatPair(state, floatPairIndex(word >> 16, bits.getBit32(word, 7)));
        const right = readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
        const result = mulFloat64(state, left, right);
        writeFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)), result);
    } else {
        const left = state.readFloatWord(floatWordIndex(word >> 16, bits.getBit32(word, 7)));
        const right = state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5)));
        const result = mulFloat32(state, left, right);
        state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), result);
    }
    state.write(.pc, pc + 4);
}

fn runFloatNegMul(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        const left = readFloatPair(state, floatPairIndex(word >> 16, bits.getBit32(word, 7)));
        const right = readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
        const result = negFloat64(mulFloat64(state, left, right));
        writeFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)), result);
    } else {
        const left = state.readFloatWord(floatWordIndex(word >> 16, bits.getBit32(word, 7)));
        const right = state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5)));
        const result = negFloat32(mulFloat32(state, left, right));
        state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), result);
    }
    state.write(.pc, pc + 4);
}

fn runFloatDiv(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        const left = readFloatPair(state, floatPairIndex(word >> 16, bits.getBit32(word, 7)));
        const right = readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
        const result = divFloat64(state, left, right);
        writeFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)), result);
    } else {
        const left = state.readFloatWord(floatWordIndex(word >> 16, bits.getBit32(word, 7)));
        const right = state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5)));
        const result = divFloat32(state, left, right);
        state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), result);
    }
    state.write(.pc, pc + 4);
}

fn runFloatMoveCoreToPairLow(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn runFloatMovePairLowToCore(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn runFloatMoveCoreToWord(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn runFloatMoveWordToCore(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn runFloatMoveTwoCoreToTwoWord(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn runFloatMoveTwoWordToTwoCore(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn runFloatMoveTwoCoreToPair(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn runFloatMovePairToTwoCore(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn runFloatMoveReg(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        const value = readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
        writeFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)), value);
    } else {
        const value = state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5)));
        state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), value);
    }
    state.write(.pc, pc + 4);
}

fn runFloatLoad(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runFloatStore(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runFloatPush(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runFloatPop(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runFloatStoreMultiple(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runFloatLoadMultiple(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runFloatAbs(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        const value = readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
        writeFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)), value & 0x7fffffffffffffff);
    } else {
        const value = state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5)));
        state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), value & 0x7fffffff);
    }
    state.write(.pc, pc + 4);
}

fn runFloatNeg(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        const value = readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
        writeFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)), negFloat64(value));
    } else {
        const value = state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5)));
        state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), negFloat32(value));
    }
    state.write(.pc, pc + 4);
}

fn runFloatSqrt(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (state.floatVectorLength() != 1 or state.floatVectorStride() != 1) {
        return runExternalArmHandler(state, hooks, pc);
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    if (bits.getBit32(word, 8)) {
        const value = readFloatPair(state, floatPairIndex(word, bits.getBit32(word, 5)));
        writeFloatPair(state, floatPairIndex(word >> 12, bits.getBit32(word, 22)), sqrtFloat64(state, value));
    } else {
        const value = state.readFloatWord(floatWordIndex(word, bits.getBit32(word, 5)));
        state.writeFloatWord(floatWordIndex(word >> 12, bits.getBit32(word, 22)), sqrtFloat32(state, value));
    }
    state.write(.pc, pc + 4);
}

fn runFloatConvertWidth(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runFloatConvertIntToFloat(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runFloatConvertToUnsigned(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runFloatConvertToSigned(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runFloatStatusWrite(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn runFloatStatusRead(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn isSignedTopMultiply(word: u32) bool {
    return (word & 0x0ff0f0d0) == 0x0750f010 or
        (word & 0x0ff000d0) == 0x07500010 or
        (word & 0x0ff000d0) == 0x075000d0;
}

fn halfMultiplyOp(word: u32) ?HalfMultiplyOp {
    if (armCondition(word) == null) {
        return null;
    }
    if ((word & 0x0ff00090) == 0x01400080) {
        return .long_add;
    }
    if ((word & 0x0ff00090) == 0x01000080) {
        return .add;
    }
    if ((word & 0x0ff0f090) == 0x01600080) {
        return .multiply;
    }
    if ((word & 0x0ff000b0) == 0x01200080) {
        return .word_add;
    }
    if ((word & 0x0ff0f0b0) == 0x012000a0) {
        return .word_multiply;
    }
    return null;
}

fn dualMultiplyOp(word: u32) ?DualMultiplyOp {
    if (armCondition(word) == null) {
        return null;
    }
    if ((word & 0x0ff0f0d0) == 0x0700f010) {
        return .pair_add;
    }
    if ((word & 0x0ff0f0d0) == 0x0700f050) {
        return .pair_sub;
    }
    if ((word & 0x0ff000d0) == 0x07000010) {
        return .add;
    }
    if ((word & 0x0ff000d0) == 0x07400010) {
        return .long_add;
    }
    if ((word & 0x0ff000d0) == 0x07000050) {
        return .sub;
    }
    if ((word & 0x0ff000d0) == 0x07400050) {
        return .long_sub;
    }
    return null;
}

fn runSignedTopMultiply(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 16);
    const addend = armReg(word >> 12);
    const right = armReg(word >> 8);
    const left = armReg(word);
    const smmul = (word & 0x0ff0f0d0) == 0x0750f010;
    const subtract = (word & 0x0ff000d0) == 0x075000d0;
    if (dest == .pc or left == .pc or right == .pc or (subtract and addend == .pc)) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const product = signedProduct(state.read(left), state.read(right));
    var wide = product;
    if (!smmul) {
        const addend_wide = @as(u64, state.read(addend)) << 32;
        wide = if (subtract) addend_wide -% product else addend_wide +% product;
    }

    var result = @intCast(u32, wide >> 32);
    if (bits.getBit32(word, 5) and ((wide & (1 << 31)) != 0)) {
        result +%= 1;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

fn runHalfMultiply(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const op = halfMultiplyOp(word).?;
    const high_or_dest = armReg(word >> 16);
    const low_or_addend = armReg(word >> 12);
    const right = armReg(word >> 8);
    const left = armReg(word);
    const left_top = bits.getBit32(word, 5);
    const right_top = bits.getBit32(word, 6);

    if (high_or_dest == .pc or left == .pc or right == .pc) {
        return error.Unpredictable;
    }
    switch (op) {
        .add, .word_add => {
            if (low_or_addend == .pc) {
                return error.Unpredictable;
            }
        },
        .long_add => {
            if (low_or_addend == .pc or low_or_addend == high_or_dest) {
                return error.Unpredictable;
            }
        },
        .multiply, .word_multiply => {},
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left_word = state.read(left);
    const right_word = state.read(right);
    const addend_word = state.read(low_or_addend);
    const addend_long = readLong(state, high_or_dest, low_or_addend);
    const left_half = selectedHalf(left_word, left_top);
    const right_half = selectedHalf(right_word, right_top);

    switch (op) {
        .long_add => {
            const product = @as(i64, left_half * right_half);
            writeLongResult(state, high_or_dest, low_or_addend, @bitCast(u64, product) +% addend_long);
        },
        .add => {
            const product = signedLowWord(@as(i64, left_half * right_half));
            const result = addWithCarry(product, addend_word, false);
            state.write(high_or_dest, result.word);
            if (result.overflow) {
                raiseQFlag(state);
            }
        },
        .multiply => {
            state.write(high_or_dest, signedLowWord(@as(i64, left_half * right_half)));
        },
        .word_add => {
            const product = (@as(i64, @bitCast(i32, left_word)) * @as(i64, right_half)) >> 16;
            const result = addWithCarry(signedLowWord(product), addend_word, false);
            state.write(high_or_dest, result.word);
            if (result.overflow) {
                raiseQFlag(state);
            }
        },
        .word_multiply => {
            const product = (@as(i64, @bitCast(i32, left_word)) * @as(i64, right_half)) >> 16;
            state.write(high_or_dest, signedLowWord(product));
        },
    }
    state.write(.pc, pc + 4);
}

fn runDualMultiply(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const op = dualMultiplyOp(word).?;
    const high_or_dest = armReg(word >> 16);
    const low_or_addend = armReg(word >> 12);
    const right = armReg(word >> 8);
    const left = armReg(word);
    const swap_right = bits.getBit32(word, 5);

    if (high_or_dest == .pc or left == .pc or right == .pc) {
        return error.Unpredictable;
    }
    switch (op) {
        .add, .sub => {},
        .long_add, .long_sub => {
            if (low_or_addend == .pc or low_or_addend == high_or_dest) {
                return error.Unpredictable;
            }
        },
        .pair_add, .pair_sub => {},
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left_word = state.read(left);
    const right_word = state.read(right);
    const addend_word = state.read(low_or_addend);
    const addend_long = readLong(state, high_or_dest, low_or_addend);
    const left_low = selectedHalf(left_word, false);
    const left_high = selectedHalf(left_word, true);
    const right_low = selectedHalf(right_word, swap_right);
    const right_high = selectedHalf(right_word, !swap_right);
    const product_low = signedLowWord(@as(i64, left_low * right_low));
    const product_high = signedLowWord(@as(i64, left_high * right_high));

    switch (op) {
        .add, .pair_add => {
            var sum = addWithCarry(product_low, product_high, false);
            if (sum.overflow) {
                raiseQFlag(state);
            }
            if (op == .add) {
                sum = addWithCarry(sum.word, addend_word, false);
                if (sum.overflow) {
                    raiseQFlag(state);
                }
            }
            state.write(high_or_dest, sum.word);
        },
        .sub, .pair_sub => {
            const difference = product_low -% product_high;
            if (op == .sub) {
                const sum = addWithCarry(difference, addend_word, false);
                state.write(high_or_dest, sum.word);
                if (sum.overflow) {
                    raiseQFlag(state);
                }
            } else {
                state.write(high_or_dest, difference);
            }
        },
        .long_add => {
            const product = @as(i64, left_low * right_low) + @as(i64, left_high * right_high);
            writeLongResult(state, high_or_dest, low_or_addend, @bitCast(u64, product) +% addend_long);
        },
        .long_sub => {
            const product = @as(i64, left_low * right_low) - @as(i64, left_high * right_high);
            writeLongResult(state, high_or_dest, low_or_addend, @bitCast(u64, product) +% addend_long);
        },
    }
    state.write(.pc, pc + 4);
}

fn addFloat32(state: *arm_state.MachineState, left: u32, right: u32) u32 {
    const left_word = floatInput32(state, left);
    const right_word = floatInput32(state, right);
    var result = @bitCast(u32, @bitCast(f32, left_word) + @bitCast(f32, right_word));
    result = floatOutput32(state, result);
    if (state.floatDefaultNaN() and isNan32(result)) {
        return 0x7fc00000;
    }
    return result;
}

fn divFloat32(state: *arm_state.MachineState, left: u32, right: u32) u32 {
    const left_word = floatInput32(state, left);
    const right_word = floatInput32(state, right);
    var result = @bitCast(u32, @bitCast(f32, left_word) / @bitCast(f32, right_word));
    result = floatOutput32(state, result);
    if (state.floatDefaultNaN() and isNan32(result)) {
        return 0x7fc00000;
    }
    return result;
}

fn mulFloat32(state: *arm_state.MachineState, left: u32, right: u32) u32 {
    const left_word = floatInput32(state, left);
    const right_word = floatInput32(state, right);
    var result = @bitCast(u32, @bitCast(f32, left_word) * @bitCast(f32, right_word));
    result = floatOutput32(state, result);
    if (state.floatDefaultNaN() and isNan32(result)) {
        return 0x7fc00000;
    }
    return result;
}

fn subFloat32(state: *arm_state.MachineState, left: u32, right: u32) u32 {
    const left_word = floatInput32(state, left);
    const right_word = floatInput32(state, right);
    var result = @bitCast(u32, @bitCast(f32, left_word) - @bitCast(f32, right_word));
    result = floatOutput32(state, result);
    if (state.floatDefaultNaN() and isNan32(result)) {
        return 0x7fc00000;
    }
    return result;
}

fn negFloat32(value: u32) u32 {
    return value ^ 0x80000000;
}

fn sqrtFloat32(state: *arm_state.MachineState, value: u32) u32 {
    const input = floatInput32(state, value);
    var result = @bitCast(u32, @sqrt(@bitCast(f32, input)));
    result = floatOutput32(state, result);
    if (state.floatDefaultNaN() and isNan32(result)) {
        return 0x7fc00000;
    }
    return result;
}

fn addFloat64(state: *arm_state.MachineState, left: u64, right: u64) u64 {
    const left_word = floatInput64(state, left);
    const right_word = floatInput64(state, right);
    var result = @bitCast(u64, @bitCast(f64, left_word) + @bitCast(f64, right_word));
    result = floatOutput64(state, result);
    if (state.floatDefaultNaN() and isNan64(result)) {
        return 0x7ff8000000000000;
    }
    return result;
}

fn divFloat64(state: *arm_state.MachineState, left: u64, right: u64) u64 {
    const left_word = floatInput64(state, left);
    const right_word = floatInput64(state, right);
    var result = @bitCast(u64, @bitCast(f64, left_word) / @bitCast(f64, right_word));
    result = floatOutput64(state, result);
    if (state.floatDefaultNaN() and isNan64(result)) {
        return 0x7ff8000000000000;
    }
    return result;
}

fn mulFloat64(state: *arm_state.MachineState, left: u64, right: u64) u64 {
    const left_word = floatInput64(state, left);
    const right_word = floatInput64(state, right);
    var result = @bitCast(u64, @bitCast(f64, left_word) * @bitCast(f64, right_word));
    result = floatOutput64(state, result);
    if (state.floatDefaultNaN() and isNan64(result)) {
        return 0x7ff8000000000000;
    }
    return result;
}

fn negFloat64(value: u64) u64 {
    return value ^ 0x8000000000000000;
}

fn sqrtFloat64(state: *arm_state.MachineState, value: u64) u64 {
    const input = floatInput64(state, value);
    var result = @bitCast(u64, @sqrt(@bitCast(f64, input)));
    result = floatOutput64(state, result);
    if (state.floatDefaultNaN() and isNan64(result)) {
        return 0x7ff8000000000000;
    }
    return result;
}

fn subFloat64(state: *arm_state.MachineState, left: u64, right: u64) u64 {
    const left_word = floatInput64(state, left);
    const right_word = floatInput64(state, right);
    var result = @bitCast(u64, @bitCast(f64, left_word) - @bitCast(f64, right_word));
    result = floatOutput64(state, result);
    if (state.floatDefaultNaN() and isNan64(result)) {
        return 0x7ff8000000000000;
    }
    return result;
}

fn convertFloat32To64(state: *arm_state.MachineState, value: u32) u64 {
    const input = floatInput32(state, value);
    var result = @bitCast(u64, @floatCast(f64, @bitCast(f32, input)));
    result = floatOutput64(state, result);
    if (state.floatDefaultNaN() and isNan64(result)) {
        return 0x7ff8000000000000;
    }
    return result;
}

fn convertFloat64To32(state: *arm_state.MachineState, value: u64) u32 {
    const input = floatInput64(state, value);
    var result = @bitCast(u32, @floatCast(f32, @bitCast(f64, input)));
    result = floatOutput32(state, result);
    if (state.floatDefaultNaN() and isNan32(result)) {
        return 0x7fc00000;
    }
    return result;
}

fn floatFromSigned32To32(state: *arm_state.MachineState, value: u32) u32 {
    return floatOutput32(state, @bitCast(u32, @intToFloat(f32, @bitCast(i32, value))));
}

fn floatFromUnsigned32To32(state: *arm_state.MachineState, value: u32) u32 {
    return floatOutput32(state, @bitCast(u32, @intToFloat(f32, value)));
}

fn floatFromSigned32To64(state: *arm_state.MachineState, value: u32) u64 {
    return floatOutput64(state, @bitCast(u64, @intToFloat(f64, @bitCast(i32, value))));
}

fn floatFromUnsigned32To64(state: *arm_state.MachineState, value: u32) u64 {
    return floatOutput64(state, @bitCast(u64, @intToFloat(f64, value)));
}

fn convertFloat32ToSigned32(state: *arm_state.MachineState, value: u32, round_towards_zero: bool) u32 {
    const rounded = roundedFloat64(state, @floatCast(f64, @bitCast(f32, floatInput32(state, value))), round_towards_zero);
    return intWordFromSignedFloat(rounded);
}

fn convertFloat64ToSigned32(state: *arm_state.MachineState, value: u64, round_towards_zero: bool) u32 {
    const rounded = roundedFloat64(state, @bitCast(f64, floatInput64(state, value)), round_towards_zero);
    return intWordFromSignedFloat(rounded);
}

fn convertFloat32ToUnsigned32(state: *arm_state.MachineState, value: u32, round_towards_zero: bool) u32 {
    const rounded = roundedFloat64(state, @floatCast(f64, @bitCast(f32, floatInput32(state, value))), round_towards_zero);
    return intWordFromUnsignedFloat(rounded);
}

fn convertFloat64ToUnsigned32(state: *arm_state.MachineState, value: u64, round_towards_zero: bool) u32 {
    const rounded = roundedFloat64(state, @bitCast(f64, floatInput64(state, value)), round_towards_zero);
    return intWordFromUnsignedFloat(rounded);
}

fn roundedFloat64(state: *const arm_state.MachineState, value: f64, round_towards_zero: bool) f64 {
    if (round_towards_zero) {
        return @trunc(value);
    }
    return switch (state.floatRoundMode()) {
        .nearest => if (value >= 0) @floor(value + 0.5) else @ceil(value - 0.5),
        .positive => @ceil(value),
        .negative => @floor(value),
        .zero => @trunc(value),
    };
}

fn intWordFromSignedFloat(value: f64) u32 {
    if (value != value) {
        return 0;
    }
    if (value >= 2147483647.0) {
        return 0x7fffffff;
    }
    if (value <= -2147483648.0) {
        return 0x80000000;
    }
    return @bitCast(u32, @floatToInt(i32, value));
}

fn intWordFromUnsignedFloat(value: f64) u32 {
    if (value != value or value <= 0.0) {
        return 0;
    }
    if (value >= 4294967295.0) {
        return 0xffffffff;
    }
    return @floatToInt(u32, value);
}

fn floatInput32(state: *arm_state.MachineState, value: u32) u32 {
    if (state.floatFlushZero() and isDenormal32(value)) {
        state.fpscr |= 1 << 7;
        return 0;
    }
    return value;
}

fn floatInput64(state: *arm_state.MachineState, value: u64) u64 {
    if (state.floatFlushZero() and isDenormal64(value)) {
        state.fpscr |= 1 << 7;
        return 0;
    }
    return value;
}

fn floatOutput32(state: *arm_state.MachineState, value: u32) u32 {
    if (state.floatFlushZero() and isDenormal32(value)) {
        state.fpscr |= 1 << 3;
        return 0;
    }
    return value;
}

fn floatOutput64(state: *arm_state.MachineState, value: u64) u64 {
    if (state.floatFlushZero() and isDenormal64(value)) {
        state.fpscr |= 1 << 3;
        return 0;
    }
    return value;
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

fn floatStackBase(word: u32, double: bool) u32 {
    const value = (word >> 12) & 0xf;
    const high = @as(u32, @boolToInt(bits.getBit32(word, 22)));
    if (double) {
        return value | (high << 4);
    }
    return (value << 1) | high;
}

fn floatStackCount(word: u32) u32 {
    if (bits.getBit32(word, 8)) {
        return (word & 0xff) >> 1;
    }
    return word & 0xff;
}

fn isLastFloatWord(reg: arm_state.FloatWordReg) bool {
    return @enumToInt(reg) == 31;
}

fn nextFloatWordReg(reg: arm_state.FloatWordReg) arm_state.FloatWordReg {
    return @intToEnum(arm_state.FloatWordReg, @intCast(u5, @enumToInt(reg) + 1));
}

fn regListCount(list: u16) u5 {
    var count: u5 = 0;
    var index: u5 = 0;
    while (index < 16) : (index += 1) {
        if ((list & (@as(u16, 1) << index)) != 0) {
            count += 1;
        }
    }
    return count;
}

fn statusWriteMask(word: u32) u32 {
    const field = (word >> 18) & 0x3;
    var mask: u32 = 0;
    if ((field & 0x2) != 0) {
        mask |= 0xf8000000;
    }
    if ((field & 0x1) != 0) {
        mask |= 0x000f0000;
    }
    return mask;
}

fn mergeStatus(old: u32, value: u32, mask: u32) u32 {
    return (old & ~mask) | (value & mask);
}

fn readFloatPair(state: *const arm_state.MachineState, reg: arm_state.FloatPairReg) u64 {
    return state.readFloatPair(reg);
}

fn writeFloatPair(state: *arm_state.MachineState, reg: arm_state.FloatPairReg, value: u64) void {
    state.writeFloatPair(reg, value);
}

fn runStatusRead(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn runStatusWriteImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn runStatusWriteRegister(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

fn runBranchLinkExchangeImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const high = @as(u32, @boolToInt(bits.getBit32(word, 24)));
    const offset = bits.signExtend32(((word & 0x00ffffff) << 2) | (high << 1), 26) + 8;
    state.write(.lr, pc + 4);
    state.setThumb(true);
    state.write(.pc, addSigned(pc, offset) & 0xfffffffe);
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

fn runBranchExchangeRegister(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        .multiply_add => {
            if (low == .pc) {
                return error.Unpredictable;
            }
        },
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

fn runLoadMultiple(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const base_reg = armReg(word >> 16);
    const list = @intCast(u16, word & 0xffff);
    const count = regListCount(list);
    if (base_reg == .pc or count == 0) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const base = state.read(base_reg);
    const span = @as(u32, count) * 4;
    const start = if (bits.getBit32(word, 24))
        if (bits.getBit32(word, 23)) base +% 4 else base -% span
    else
        if (bits.getBit32(word, 23)) base else base -% span +% 4;
    const writeback = if (bits.getBit32(word, 24))
        if (bits.getBit32(word, 23)) base +% span else base -% span
    else
        if (bits.getBit32(word, 23)) base +% span else start -% 4;

    var address = start;
    var index: u5 = 0;
    while (index < 15) : (index += 1) {
        if ((list & (@as(u16, 1) << index)) != 0) {
            state.write(@intToEnum(arm_state.ArmReg, @intCast(u8, index)), try readMemory32(state, hooks, address));
            address +%= 4;
        }
    }

    if (bits.getBit32(word, 21) and (list & (@as(u16, 1) << @enumToInt(base_reg))) == 0) {
        state.write(base_reg, writeback);
    }

    if ((list & 0x8000) != 0) {
        loadWritePc(state, try readMemory32(state, hooks, address));
        return;
    }
    state.write(.pc, pc + 4);
}

fn runStoreMultiple(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    const base_reg = armReg(word >> 16);
    const list = @intCast(u16, word & 0xffff);
    const count = regListCount(list);
    if (base_reg == .pc or count == 0) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const base = state.read(base_reg);
    const span = @as(u32, count) * 4;
    const start = if (bits.getBit32(word, 24))
        if (bits.getBit32(word, 23)) base +% 4 else base -% span
    else
        if (bits.getBit32(word, 23)) base else base -% span +% 4;
    const writeback = if (bits.getBit32(word, 24))
        if (bits.getBit32(word, 23)) base +% span else base -% span
    else
        if (bits.getBit32(word, 23)) base +% span else start -% 4;

    var address = start;
    var index: u5 = 0;
    while (index < 15) : (index += 1) {
        if ((list & (@as(u16, 1) << index)) != 0) {
            try writeMemory32(state, hooks, address, state.read(@intToEnum(arm_state.ArmReg, @intCast(u8, index))));
            address +%= 4;
        }
    }

    if (bits.getBit32(word, 21)) {
        state.write(base_reg, writeback);
    }

    if ((list & 0x8000) != 0) {
        try writeMemory32(state, hooks, address, pc);
    }
    state.write(.pc, pc + 4);
}

fn runUnsignedSaturatingSubBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    var result: u32 = 0;
    var index: u5 = 0;
    while (index < 4) : (index += 1) {
        const shift = @intCast(u5, index * 8);
        const left_byte = @intCast(u8, (left >> shift) & 0xff);
        const right_byte = @intCast(u8, (right >> shift) & 0xff);
        const byte = if (left_byte > right_byte) left_byte - right_byte else 0;
        result |= @as(u32, byte) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

fn runSignedSaturatingSubBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    var result: u32 = 0;
    var index: u5 = 0;
    while (index < 4) : (index += 1) {
        const shift = @intCast(u5, index * 8);
        const lane = clampSignedByte(signedByte(left >> shift) - signedByte(right >> shift));
        const encoded = if (lane < 0) @intCast(u8, lane + 256) else @intCast(u8, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

fn runUnsignedSaturatingAddBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    var result: u32 = 0;
    var index: u5 = 0;
    while (index < 4) : (index += 1) {
        const shift = @intCast(u5, index * 8);
        const left_byte = (left >> shift) & 0xff;
        const right_byte = (right >> shift) & 0xff;
        const sum = left_byte + right_byte;
        const byte = if (sum > 0xff) @as(u32, 0xff) else sum;
        result |= byte << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

fn runSignedSaturatingAddBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    var result: u32 = 0;
    var index: u5 = 0;
    while (index < 4) : (index += 1) {
        const shift = @intCast(u5, index * 8);
        const lane = clampSignedByte(signedByte(left >> shift) + signedByte(right >> shift));
        const encoded = if (lane < 0) @intCast(u8, lane + 256) else @intCast(u8, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

fn runUnsignedSaturatingSubHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    var result: u32 = 0;
    var index: u5 = 0;
    while (index < 2) : (index += 1) {
        const shift = @intCast(u5, index * 16);
        const left_half = @intCast(u16, (left >> shift) & 0xffff);
        const right_half = @intCast(u16, (right >> shift) & 0xffff);
        const half = if (left_half > right_half) left_half - right_half else 0;
        result |= @as(u32, half) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

fn runSignedSaturatingSubHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    var result: u32 = 0;
    var index: u5 = 0;
    while (index < 2) : (index += 1) {
        const shift = @intCast(u5, index * 16);
        const lane = clampSignedHalfWord(signedHalf(left >> shift) - signedHalf(right >> shift));
        const encoded = if (lane < 0) @intCast(u16, lane + 65536) else @intCast(u16, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

fn runUnsignedSaturatingAddHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    var result: u32 = 0;
    var index: u5 = 0;
    while (index < 2) : (index += 1) {
        const shift = @intCast(u5, index * 16);
        const left_half = (left >> shift) & 0xffff;
        const right_half = (right >> shift) & 0xffff;
        const sum = left_half + right_half;
        const half = if (sum > 0xffff) @as(u32, 0xffff) else sum;
        result |= half << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

fn runSignedSaturatingAddHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    var result: u32 = 0;
    var index: u5 = 0;
    while (index < 2) : (index += 1) {
        const shift = @intCast(u5, index * 16);
        const lane = clampSignedHalfWord(signedHalf(left >> shift) + signedHalf(right >> shift));
        const encoded = if (lane < 0) @intCast(u16, lane + 65536) else @intCast(u16, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

fn runLoadExclusive(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runStoreExclusive(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runSwap(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runLoadWord(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectWordLoad(word);

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
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectNarrowLoad(word);

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
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectNarrowLoad(word);

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

fn runLoadSignedByte(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectNarrowLoad(word);

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

    const data = signExtendByte(try readMemory8(hooks, address));
    if (dest == .pc) {
        writeArmAluPc(state, data +% 4);
        return;
    }
    state.write(dest, data);
    state.write(.pc, pc + 4);
}

fn runLoadSignedHalf(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectNarrowLoad(word);

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

    const data = signExtendHalf(try readMemory16(state, hooks, address));
    if (dest == .pc) {
        writeArmAluPc(state, data +% 4);
        return;
    }
    state.write(dest, data);
    state.write(.pc, pc + 4);
}

fn runLoadDouble(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (isTransferUserMode(word)) {
        return runExternalArmHandler(state, hooks, pc);
    }
    try rejectDoubleLoad(word);

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

fn runStoreByte(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runStoreHalf(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn runStoreDouble(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
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

fn rejectBadRegisterShift(word: u32, op: DataOp) ArmStepError!void {
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

fn isTransferUserMode(word: u32) bool {
    return !bits.getBit32(word, 24) and bits.getBit32(word, 21);
}

fn transferWritesBack(word: u32) bool {
    return !bits.getBit32(word, 24) or bits.getBit32(word, 21);
}

fn isWordTransferRegisterOffset(word: u32) bool {
    return bits.getBit32(word, 25);
}

fn isHalfTransferRegisterOffset(word: u32) bool {
    return !bits.getBit32(word, 22);
}

fn rejectWordLoad(word: u32) ArmStepError!void {
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

fn rejectNarrowLoad(word: u32) ArmStepError!void {
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

fn rejectDoubleLoad(word: u32) ArmStepError!void {
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

fn rejectDoubleStore(word: u32) ArmStepError!void {
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

fn rejectSingleStore(word: u32, reject_pc_source: bool, register_offset: bool) ArmStepError!void {
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

fn raiseQFlag(state: *arm_state.MachineState) void {
    state.cpsr = bits.setBit32(state.cpsr, 27, true);
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

fn exclusiveHolds(state: *const arm_state.MachineState, address: u32) bool {
    return state.exclusive and (((address ^ state.exclusive_address) & 0xfffffff8) == 0);
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
    var value = if (hooks.readDirect32(address)) |direct| direct else blk: {
        const read32 = hooks.read32 orelse return error.MissingRead;
        break :blk read32(address);
    };
    if (state.bigEndian()) {
        value = byteReverseWord(value);
    }
    return value;
}

fn readMemory8(hooks: arm_state.HostHooks, address: u32) ArmStepError!u8 {
    if (hooks.readDirect8(address)) |value| {
        return value;
    }
    const read8 = hooks.read8 orelse return error.MissingRead;
    return read8(address);
}

fn readMemory16(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32) ArmStepError!u16 {
    var value = if (hooks.readDirect16(address)) |direct| direct else blk: {
        const read16 = hooks.read16 orelse return error.MissingRead;
        break :blk read16(address);
    };
    if (state.bigEndian()) {
        value = @intCast(u16, byteReverseHalf(value));
    }
    return value;
}

fn writeMemory32(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32, value: u32) ArmStepError!void {
    var data = value;
    if (state.bigEndian()) {
        data = byteReverseWord(data);
    }
    if (hooks.writeDirect32(address, data)) {
        return;
    }
    const write32 = hooks.write32 orelse return error.MissingWrite;
    write32(address, data);
}

fn writeMemory16(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32, value: u16) ArmStepError!void {
    var data = value;
    if (state.bigEndian()) {
        data = @intCast(u16, byteReverseHalf(data));
    }
    if (hooks.writeDirect16(address, data)) {
        return;
    }
    const write16 = hooks.write16 orelse return error.MissingWrite;
    write16(address, data);
}

fn writeMemory8(hooks: arm_state.HostHooks, address: u32, value: u8) ArmStepError!void {
    if (hooks.writeDirect8(address, value)) {
        return;
    }
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

fn signedByte(value: u32) i16 {
    const narrowed = @intCast(i16, value & 0xff);
    if ((narrowed & 0x80) != 0) {
        return narrowed - 256;
    }
    return narrowed;
}

fn clampSignedByte(value: i16) i16 {
    if (value > 127) {
        return 127;
    }
    if (value < -128) {
        return -128;
    }
    return value;
}

fn signedHalf(value: u32) i32 {
    const narrowed = @intCast(i32, value & 0xffff);
    if ((narrowed & 0x8000) != 0) {
        return narrowed - 65536;
    }
    return narrowed;
}

fn clampSignedHalfWord(value: i32) i32 {
    if (value > 32767) {
        return 32767;
    }
    if (value < -32768) {
        return -32768;
    }
    return value;
}

fn signExtendHalf(value: u32) u32 {
    const narrowed = value & 0xffff;
    if ((narrowed & 0x8000) != 0) {
        return narrowed | 0xffff0000;
    }
    return narrowed;
}

fn selectedHalf(value: u32, high: bool) i32 {
    return signedHalf(if (high) value >> 16 else value);
}

fn signedLowWord(value: i64) u32 {
    return @intCast(u32, @bitCast(u64, value) & 0xffffffff);
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
