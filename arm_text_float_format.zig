const std = @import("std");
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
    return (word & 0x0ff3f000) == 0x0320f000 and arm_state.conditionFromNibble(@intCast(u4, word >> 28)) != null;
}

pub fn isStatusWriteRegister(word: u32) bool {
    return (word & 0x0ff3fff0) == 0x0120f000 and arm_state.conditionFromNibble(@intCast(u4, word >> 28)) != null;
}

pub fn formatFloatAdd(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vadd{}.f64 d{}, d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vadd{}.f32 s{}, s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatThree(buf: []u8, word: u32, cond: u4, name: []const u8) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "{}{}.f64 d{}, d{}, d{}", .{
            name,
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{}.f32 s{}, s{}, s{}", .{
        name,
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatSub(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vsub{}.f64 d{}, d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vsub{}.f32 s{}, s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMul(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vmul{}.f64 d{}, d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vmul{}.f32 s{}, s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatNegMul(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vnmul{}.f64 d{}, d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vnmul{}.f32 s{}, s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatDiv(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vdiv{}.f64 d{}, d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vdiv{}.f32 s{}, s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveCoreToPairLow(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{}.32 d{}, {}", .{
        condName(cond),
        floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
        arm_state.regName(armReg(word >> 12)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMovePairLowToCore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{}.32 {}, d{}", .{
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveCoreToWord(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{}.32 s{}, {}", .{
        condName(cond),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        arm_state.regName(armReg(word >> 12)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveWordToCore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{}.32 {}, s{}", .{
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveTwoCoreToTwoWord(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const first = floatWordTextIndex(word, bits.getBit32(word, 5));
    return std.fmt.bufPrint(buf, "vmov{} s{}, s{}, {}, {}", .{
        condName(cond),
        first,
        first + 1,
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveTwoWordToTwoCore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const first = floatWordTextIndex(word, bits.getBit32(word, 5));
    return std.fmt.bufPrint(buf, "vmov{} {}, {}, s{}, s{}", .{
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
        first,
        first + 1,
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveTwoCoreToPair(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{} d{}, {}, {}", .{
        condName(cond),
        floatPairTextIndex(word, bits.getBit32(word, 5)),
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMovePairToTwoCore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{} {}, {}, d{}", .{
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
        floatPairTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveReg(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vmov{}.f64 d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vmov{}.f32 s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatLoad(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const suffix = if (bits.getBit32(word, 23)) "+" else "-";
    const offset = (word & 0xff) << 2;
    const base = armReg(word >> 16);
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vldr{} d{}, [{}, #{}{}]", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            arm_state.regName(base),
            suffix,
            offset,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vldr{} s{}, [{}, #{}{}]", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        arm_state.regName(base),
        suffix,
        offset,
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatStore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const suffix = if (bits.getBit32(word, 23)) "+" else "-";
    const offset = (word & 0xff) << 2;
    const base = armReg(word >> 16);
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vstr{} d{}, [{}, #{}{}]", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            arm_state.regName(base),
            suffix,
            offset,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vstr{} s{}, [{}, #{}{}]", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        arm_state.regName(base),
        suffix,
        offset,
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatStack(buf: []u8, word: u32, cond: u4, name: []const u8) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "{}{} d{}(+{})", .{
            name,
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            (word & 0xff) >> 1,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{} s{}(+{})", .{
        name,
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        word & 0xff,
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatStoreMultiple(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const mode = if (!bits.getBit32(word, 24) and bits.getBit32(word, 23)) "ia" else if (bits.getBit32(word, 24) and !bits.getBit32(word, 23)) "db" else "??";
    const marker = if (bits.getBit32(word, 21)) "!" else "";
    const base = armReg(word >> 16);
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vstm{}{}.f64 {}{}, d{}(+{})", .{
            mode,
            condName(cond),
            arm_state.regName(base),
            marker,
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            (word & 0xff) >> 1,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vstm{}{}.f32 {}{}, s{}(+{})", .{
        mode,
        condName(cond),
        arm_state.regName(base),
        marker,
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        word & 0xff,
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatLoadMultiple(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const mode = if (!bits.getBit32(word, 24) and bits.getBit32(word, 23)) "ia" else if (bits.getBit32(word, 24) and !bits.getBit32(word, 23)) "db" else "??";
    const marker = if (bits.getBit32(word, 21)) "!" else "";
    const base = armReg(word >> 16);
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vldm{}{}.f64 {}{}, d{}(+{})", .{
            mode,
            condName(cond),
            arm_state.regName(base),
            marker,
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            (word & 0xff) >> 1,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vldm{}{}.f32 {}{}, s{}(+{})", .{
        mode,
        condName(cond),
        arm_state.regName(base),
        marker,
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        word & 0xff,
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatAbs(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vabs{}.f64 d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vabs{}.f32 s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatNeg(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vneg{}.f64 d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vneg{}.f32 s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatSqrt(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vsqrt{}.f64 d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vsqrt{}.f32 s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatConvertWidth(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vcvt{}.f32.f64 s{}, d{}", .{
            condName(cond),
            floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vcvt{}.f64.f32 d{}, s{}", .{
        condName(cond),
        floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatConvertIntToFloat(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const int_type = if (bits.getBit32(word, 7)) "s32" else "u32";
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vcvt{}.f64.{} d{}, s{}", .{
            condName(cond),
            int_type,
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatWordTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vcvt{}.f32.{} s{}, s{}", .{
        condName(cond),
        int_type,
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatConvertToInt(buf: []u8, word: u32, cond: u4, int_type: []const u8) TextError![]u8 {
    const rounded = if (bits.getBit32(word, 7)) "" else "r";
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vcvt{}{}.{}.f64 s{}, d{}", .{
            rounded,
            condName(cond),
            int_type,
            floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vcvt{}{}.{}.f32 s{}, s{}", .{
        rounded,
        condName(cond),
        int_type,
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatCompare(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const op = if (bits.getBit32(word, 7)) "vcmpe" else "vcmp";
    const zero = (word & 0x0fbf0e7f) == 0x0eb50a40;
    if (bits.getBit32(word, 8)) {
        if (zero) {
            return std.fmt.bufPrint(buf, "{}{}.f64 d{}, #0.0", .{
                op,
                condName(cond),
                floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            }) catch error.NoSpaceLeft;
        }
        return std.fmt.bufPrint(buf, "{}{}.f64 d{}, d{}", .{
            op,
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    if (zero) {
        return std.fmt.bufPrint(buf, "{}{}.f32 s{}, #0.0", .{
            op,
            condName(cond),
            floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{}.f32 s{}, s{}", .{
        op,
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatStatusWrite(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const source = armReg(word >> 12);
    return std.fmt.bufPrint(buf, "vmsr{} fpscr, {}", .{
        condName(cond),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatStatusRead(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const dest = armReg(word >> 12);
    if (dest == .pc) {
        return std.fmt.bufPrint(buf, "vmrs{} apsr_nzcv, fpscr", .{condName(cond)}) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vmrs{} {}, fpscr", .{
        condName(cond),
        arm_state.regName(dest),
    }) catch error.NoSpaceLeft;
}

pub fn floatWordTextIndex(value: u32, high: bool) u32 {
    return ((value & 0xf) << 1) | @as(u32, @boolToInt(high));
}

pub fn floatPairTextIndex(value: u32, high: bool) u32 {
    return (value & 0xf) | (@as(u32, @boolToInt(high)) << 4);
}

pub fn statusMaskName(word: u32) TextError![]const u8 {
    return switch ((word >> 18) & 0x3) {
        0x1 => "g",
        0x2 => "nzcvq",
        0x3 => "nzcvqg",
        else => error.UnknownInstruction,
    };
}

pub fn formatStatusRead(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const dest = armReg(word >> 12);
    return std.fmt.bufPrint(buf, "mrs{} {}, apsr", .{
        condName(cond),
        arm_state.regName(dest),
    }) catch error.NoSpaceLeft;
}

pub fn formatStatusWriteImmediate(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "msr{} apsr_{}, #{}", .{
        condName(cond),
        try statusMaskName(word),
        arm_exec.expandArmImmediate(@intCast(u8, (word >> 8) & 0xf), @intCast(u8, word & 0xff)),
    }) catch error.NoSpaceLeft;
}

pub fn formatStatusWriteRegister(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const source = armReg(word);
    return std.fmt.bufPrint(buf, "msr{} apsr_{}, {}", .{
        condName(cond),
        try statusMaskName(word),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

