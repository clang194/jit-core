const arm_state = @import("arm_state.zig");
const bits = @import("bits.zig");
usingnamespace @import("arm_exec_types.zig");
usingnamespace @import("arm_exec_fetch_decode.zig");
usingnamespace @import("arm_exec_dispatch.zig");
usingnamespace @import("arm_exec_coprocessor.zig");
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

pub fn isHintNoOp(word: u32) bool {
    return (word & 0xfd70f000) == 0xf550f000 or
        (word & 0x0fffffff) == 0x0320f004 or
        (word & 0x0fffffff) == 0x0320f002 or
        (word & 0x0fffffff) == 0x0320f003 or
        (word & 0x0fffffff) == 0x0320f001;
}

pub fn isArmNoOp(word: u32) bool {
    return (word & 0x0fffffff) == 0x0320f000;
}

pub fn isFloatAdd(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e300a00;
}

pub fn isFloatMulAdd(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e000a00;
}

pub fn isFloatMulSub(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e000a40;
}

pub fn isFloatNegMulSub(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e100a00;
}

pub fn isFloatNegMulAdd(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e100a40;
}

pub fn isFloatSub(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e300a40;
}

pub fn isFloatMul(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e200a00;
}

pub fn isFloatNegMul(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e200a40;
}

pub fn isFloatDiv(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fb00f50) == 0x0e800a00;
}

pub fn isFloatMoveCoreToPairLow(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00f7f) == 0x0e000b10;
}

pub fn isFloatMovePairLowToCore(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00f7f) == 0x0e100b10;
}

pub fn isFloatMoveCoreToWord(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00f7f) == 0x0e000a10;
}

pub fn isFloatMoveWordToCore(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00f7f) == 0x0e100a10;
}

pub fn isFloatMoveTwoCoreToTwoWord(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00fd0) == 0x0c400a10;
}

pub fn isFloatMoveTwoWordToTwoCore(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00fd0) == 0x0c500a10;
}

pub fn isFloatMoveTwoCoreToPair(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00fd0) == 0x0c400b10;
}

pub fn isFloatMovePairToTwoCore(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0ff00fd0) == 0x0c500b10;
}

pub fn isFloatMoveReg(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0ed0) == 0x0eb00a40;
}

pub fn isFloatLoad(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0f300e00) == 0x0d100a00;
}

pub fn isFloatStore(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0f300e00) == 0x0d000a00;
}

pub fn isFloatPush(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0e00) == 0x0d2d0a00;
}

pub fn isFloatStoreMultiple(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0e100e00) == 0x0c000a00;
}

pub fn isFloatPop(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0e00) == 0x0cbd0a00;
}

pub fn isFloatLoadMultiple(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0e100e00) == 0x0c100a00;
}

pub fn isFloatAbs(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0ed0) == 0x0eb00ac0;
}

pub fn isFloatNeg(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0ed0) == 0x0eb10a40;
}

pub fn isFloatSqrt(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0ed0) == 0x0eb10ac0;
}

pub fn isFloatConvertWidth(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0ed0) == 0x0eb70ac0;
}

pub fn isFloatConvertIntToFloat(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0e50) == 0x0eb80a40;
}

pub fn isFloatConvertToUnsigned(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0e50) == 0x0ebc0a40;
}

pub fn isFloatConvertToSigned(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fbf0e50) == 0x0ebd0a40;
}

pub fn isFloatCompare(word: u32) bool {
    return isVfpCondition(word) and ((word & 0x0fbf0e50) == 0x0eb40a40 or
        (word & 0x0fbf0e7f) == 0x0eb50a40);
}

pub fn isFloatStatusWrite(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fff0fff) == 0x0ee10a10;
}

pub fn isFloatStatusRead(word: u32) bool {
    return isVfpCondition(word) and (word & 0x0fff0fff) == 0x0ef10a10;
}

pub fn isVfpCondition(word: u32) bool {
    return (word >> 28) != 0xf;
}

