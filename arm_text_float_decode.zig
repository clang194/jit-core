const std = @import("std");
const text_types = @import("arm_text_types.zig");
const TextError = text_types.TextError;
const bits = @import("bits.zig");
const arm_exec = @import("arm_exec.zig");
const arm_state = @import("arm_state.zig");
usingnamespace @import("arm_text_types.zig");
usingnamespace @import("arm_text_arm_format.zig");
usingnamespace @import("arm_text_coprocessor_format.zig");
usingnamespace @import("arm_text_block_format.zig");
usingnamespace @import("arm_text_misc_format.zig");
usingnamespace @import("arm_text_parallel_format.zig");
usingnamespace @import("arm_text_multiply_format.zig");
usingnamespace @import("arm_text_transfer_format.zig");
usingnamespace @import("arm_text_data_format.zig");
usingnamespace @import("arm_text_thumb_format.zig");
usingnamespace @import("arm_text_thumb32_format.zig");
usingnamespace @import("arm_text_common_format.zig");

pub const ArmExtendText = struct {
    name: []const u8,
    base: bool,
};

pub fn formatArmExtend(buf: []u8, word: u32, info: ArmExtendText) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    var source_buf: [32]u8 = undefined;
    const source = try formatExtendSource(source_buf[0..], word);
    if (info.base) {
        const base = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
        return std.fmt.bufPrint(buf, "{}{} {}, {}, {}", .{
            info.name,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
            source,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{} {}, {}", .{
        info.name,
        condName(cond),
        arm_state.regName(dest),
        source,
    }) catch error.NoSpaceLeft;
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

pub fn isStatusRead(word: u32) bool {
    return (word & 0x0fff0fff) == 0x010f0000 and arm_state.conditionFromNibble(@intCast(u4, word >> 28)) != null;
}

pub fn isStatusWriteImmediate(word: u32) bool {
    return (word & 0x0ff0f000) == 0x0320f000 and arm_state.conditionFromNibble(@intCast(u4, word >> 28)) != null;
}

pub fn isStatusWriteRegister(word: u32) bool {
    return (word & 0x0ff0fff0) == 0x0120f000 and arm_state.conditionFromNibble(@intCast(u4, word >> 28)) != null;
}
