const arm_state = @import("arm_state.zig");
const bits = @import("bits.zig");
usingnamespace @import("arm_exec_types.zig");
usingnamespace @import("arm_exec_dispatch.zig");
usingnamespace @import("arm_exec_coprocessor.zig");
usingnamespace @import("arm_exec_float_decode.zig");
usingnamespace @import("arm_exec_float_run.zig");
usingnamespace @import("arm_exec_multiply_run.zig");
usingnamespace @import("arm_exec_float_math.zig");
usingnamespace @import("arm_exec_divide_run.zig");
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

pub fn readArmWord(hooks: arm_state.HostHooks, pc: u32) ArmStepError!u32 {
    const address = pc & 0xfffffffc;
    if (hooks.memory.fetch32) |fetch32| {
        return fetch32(address);
    }
    if (hooks.memory.readDirect32(address)) |value| {
        return value;
    }
    const read32 = hooks.memory.read32 orelse return error.MissingRead;
    return read32(address);
}

pub fn isSupervisorCall(word: u32) bool {
    return (word & 0x0f000000) == 0x0f000000 and armCondition(word) != null;
}

pub fn supervisorImmediate(word: u32) u32 {
    return word & 0x00ffffff;
}

pub fn isUndefinedInstruction(word: u32) bool {
    return (word & 0xfff000f0) == 0xe7f000f0;
}

pub fn isBreakpoint(word: u32) bool {
    return (word & 0x0ff000f0) == 0x01200070 and armCondition(word) != null;
}

pub fn isBranchImmediate(word: u32) bool {
    return (word & 0x0e000000) == 0x0a000000 and armCondition(word) != null;
}

pub fn isBranchExchange(word: u32) bool {
    return (word & 0x0ffffff0) == 0x012fff10 and armCondition(word) != null;
}

pub fn isBranchExchangeRegister(word: u32) bool {
    return ((word & 0x0ffffff0) == 0x012fff10 or
        (word & 0x0ffffff0) == 0x012fff20 or
        (word & 0x0ffffff0) == 0x012fff30) and armCondition(word) != null;
}

pub fn isBranchLinkExchangeImmediate(word: u32) bool {
    return (word & 0xfe000000) == 0xfa000000;
}

pub fn isClearExclusive(word: u32) bool {
    return word == 0xf57ff01f;
}

pub fn isLoadExclusive(word: u32) bool {
    return ((word & 0x0ff00fff) == 0x01900f9f or
        (word & 0x0ff00fff) == 0x01d00f9f or
        (word & 0x0ff00fff) == 0x01b00f9f or
        (word & 0x0ff00fff) == 0x01f00f9f) and armCondition(word) != null;
}

pub fn isStoreExclusive(word: u32) bool {
    return ((word & 0x0ff00ff0) == 0x01800f90 or
        (word & 0x0ff00ff0) == 0x01c00f90 or
        (word & 0x0ff00ff0) == 0x01a00f90 or
        (word & 0x0ff00ff0) == 0x01e00f90) and armCondition(word) != null;
}

pub fn isSwap(word: u32) bool {
    return ((word & 0x0ff00ff0) == 0x01000090 or
        (word & 0x0ff00ff0) == 0x01400090) and armCondition(word) != null;
}

pub fn isEndianSelect(word: u32) bool {
    return (word & 0xfffffdff) == 0xf1010000;
}

pub fn isStatusRead(word: u32) bool {
    return (word & 0x0fff0fff) == 0x010f0000 and armCondition(word) != null;
}

pub fn isStatusWriteImmediate(word: u32) bool {
    return (word & 0x0ff0f000) == 0x0320f000 and armCondition(word) != null;
}

pub fn isStatusWriteRegister(word: u32) bool {
    return (word & 0x0ff0fff0) == 0x0120f000 and armCondition(word) != null;
}

pub fn isCountLeadingZeros(word: u32) bool {
    return (word & 0x0fff0ff0) == 0x016f0f10 and armCondition(word) != null;
}

pub fn isArmDivide(word: u32) bool {
    const op = word & 0x0ff0f0f0;
    return (op == 0x0710f010 or op == 0x0730f010) and armCondition(word) != null;
}

pub fn isBitReverse(word: u32) bool {
    return (word & 0x0fff0ff0) == 0x06ff0f30 and armCondition(word) != null;
}

pub fn isBitfieldClear(word: u32) bool {
    return (word & 0x0fe0007f) == 0x07c0001f and armCondition(word) != null;
}

pub fn isBitfieldInsert(word: u32) bool {
    return (word & 0x0fe00070) == 0x07c00010 and armCondition(word) != null;
}

pub fn isUnsignedBitfieldExtract(word: u32) bool {
    return (word & 0x0fe00070) == 0x07e00050 and armCondition(word) != null;
}

pub fn isSignedBitfieldExtract(word: u32) bool {
    return (word & 0x0fe00070) == 0x07a00050 and armCondition(word) != null;
}

pub fn isMoveTop(word: u32) bool {
    return (word & 0x0ff00000) == 0x03400000 and armCondition(word) != null;
}

pub fn isSignedSaturatingWord(word: u32) bool {
    const op = word & 0x0ff00ff0;
    return (op == 0x01000050 or
        op == 0x01200050 or
        op == 0x01400050 or
        op == 0x01600050) and armCondition(word) != null;
}

pub fn isScalarSaturatingMove(word: u32) bool {
    return ((word & 0x0fe00030) == 0x06a00010 or
        (word & 0x0fe00030) == 0x06e00010) and armCondition(word) != null;
}

pub fn isHalfSaturatingMove(word: u32) bool {
    return ((word & 0x0ff00ff0) == 0x06a00f30 or
        (word & 0x0ff00ff0) == 0x06e00f30) and armCondition(word) != null;
}

pub fn isUnsignedSaturatingSubBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06600ff0 and armCondition(word) != null;
}

pub fn isSignedSaturatingSubBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06200ff0 and armCondition(word) != null;
}

pub fn isUnsignedSaturatingAddBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06600f90 and armCondition(word) != null;
}

pub fn isSignedSaturatingAddBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06200f90 and armCondition(word) != null;
}

pub fn isUnsignedSaturatingSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06600f70 and armCondition(word) != null;
}

pub fn isSignedSaturatingSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06200f70 and armCondition(word) != null;
}

pub fn isUnsignedSaturatingAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06600f10 and armCondition(word) != null;
}

pub fn isSignedSaturatingAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06200f10 and armCondition(word) != null;
}

pub fn isUnsignedSaturatingAddSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06600f30 and armCondition(word) != null;
}

pub fn isUnsignedSaturatingSubAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06600f50 and armCondition(word) != null;
}

pub fn isSignedSaturatingAddSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06200f30 and armCondition(word) != null;
}

pub fn isSignedSaturatingSubAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06200f50 and armCondition(word) != null;
}

pub fn isUnsignedHalvingAddBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06700f90 and armCondition(word) != null;
}

pub fn isUnsignedHalvingAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06700f10 and armCondition(word) != null;
}

pub fn isSignedHalvingAddBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06300f90 and armCondition(word) != null;
}

pub fn isSignedHalvingAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06300f10 and armCondition(word) != null;
}

pub fn isUnsignedHalvingAddSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06700f30 and armCondition(word) != null;
}

pub fn isUnsignedHalvingSubAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06700f50 and armCondition(word) != null;
}

pub fn isSignedHalvingAddSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06300f30 and armCondition(word) != null;
}

pub fn isSignedHalvingSubAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06300f50 and armCondition(word) != null;
}

pub fn isUnsignedWrappingAddSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06500f30 and armCondition(word) != null;
}

pub fn isUnsignedWrappingSubAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06500f50 and armCondition(word) != null;
}

pub fn isSignedWrappingAddSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06100f30 and armCondition(word) != null;
}

pub fn isSignedWrappingSubAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06100f50 and armCondition(word) != null;
}

pub fn isUnsignedHalvingSubBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06700ff0 and armCondition(word) != null;
}

pub fn isSignedHalvingSubBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06300ff0 and armCondition(word) != null;
}

pub fn isUnsignedHalvingSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06700f70 and armCondition(word) != null;
}

pub fn isSignedHalvingSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06300f70 and armCondition(word) != null;
}

pub fn isUnsignedWrappingAddBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06500f90 and armCondition(word) != null;
}

pub fn isSignedWrappingAddBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06100f90 and armCondition(word) != null;
}

pub fn isUnsignedWrappingAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06500f10 and armCondition(word) != null;
}

pub fn isSignedWrappingAddHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06100f10 and armCondition(word) != null;
}

pub fn isUnsignedWrappingSubBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06500ff0 and armCondition(word) != null;
}

pub fn isSignedWrappingSubBytes(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06100ff0 and armCondition(word) != null;
}

pub fn isUnsignedWrappingSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06500f70 and armCondition(word) != null;
}

pub fn isSignedWrappingSubHalves(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06100f70 and armCondition(word) != null;
}

pub fn isByteSelect(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06800fb0 and armCondition(word) != null;
}

pub fn isUnsignedAbsDiffSum(word: u32) bool {
    return ((word & 0x0ff0f0f0) == 0x0780f010 or
        (word & 0x0ff000f0) == 0x07800010) and armCondition(word) != null;
}

pub fn isHalfwordPack(word: u32) bool {
    return ((word & 0x0ff00070) == 0x06800010 or
        (word & 0x0ff00070) == 0x06800050) and armCondition(word) != null;
}

pub fn isMultiply(word: u32) bool {
    return multiplyOp(word) != null;
}

pub fn isLoadMultiple(word: u32) bool {
    return (word & 0x0e500000) == 0x08100000 and armCondition(word) != null;
}

pub fn isStoreMultiple(word: u32) bool {
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
