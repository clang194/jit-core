const std = @import("std");
const bits = @import("bits.zig");
const arm_exec = @import("arm_exec.zig");
const arm_state = @import("arm_state.zig");

pub const TextError = error{
    UnknownInstruction,
    NoSpaceLeft,
};

pub fn formatArm(buf: []u8, word: u32) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    if (isFloatAdd(word)) {
        return formatFloatAdd(buf, word, cond);
    }

    if (isFloatMulAdd(word)) {
        return formatFloatThree(buf, word, cond, "vmla");
    }

    if (isFloatMulSub(word)) {
        return formatFloatThree(buf, word, cond, "vmls");
    }

    if (isFloatNegMulAdd(word)) {
        return formatFloatThree(buf, word, cond, "vnmla");
    }

    if (isFloatNegMulSub(word)) {
        return formatFloatThree(buf, word, cond, "vnmls");
    }

    if (isFloatSub(word)) {
        return formatFloatSub(buf, word, cond);
    }

    if (isFloatMul(word)) {
        return formatFloatMul(buf, word, cond);
    }

    if (isFloatNegMul(word)) {
        return formatFloatNegMul(buf, word, cond);
    }

    if (isFloatDiv(word)) {
        return formatFloatDiv(buf, word, cond);
    }

    if (isFloatMoveCoreToPairLow(word)) {
        return formatFloatMoveCoreToPairLow(buf, word, cond);
    }

    if (isFloatMovePairLowToCore(word)) {
        return formatFloatMovePairLowToCore(buf, word, cond);
    }

    if (isFloatMoveCoreToWord(word)) {
        return formatFloatMoveCoreToWord(buf, word, cond);
    }

    if (isFloatMoveWordToCore(word)) {
        return formatFloatMoveWordToCore(buf, word, cond);
    }

    if (isFloatMoveTwoCoreToTwoWord(word)) {
        return formatFloatMoveTwoCoreToTwoWord(buf, word, cond);
    }

    if (isFloatMoveTwoWordToTwoCore(word)) {
        return formatFloatMoveTwoWordToTwoCore(buf, word, cond);
    }

    if (isFloatMoveTwoCoreToPair(word)) {
        return formatFloatMoveTwoCoreToPair(buf, word, cond);
    }

    if (isFloatMovePairToTwoCore(word)) {
        return formatFloatMovePairToTwoCore(buf, word, cond);
    }

    if (isFloatMoveReg(word)) {
        return formatFloatMoveReg(buf, word, cond);
    }

    if (isFloatLoad(word)) {
        return formatFloatLoad(buf, word, cond);
    }

    if (isFloatStore(word)) {
        return formatFloatStore(buf, word, cond);
    }

    if (isFloatPush(word)) {
        return formatFloatStack(buf, word, cond, "vpush");
    }

    if (isFloatStoreMultiple(word)) {
        return formatFloatStoreMultiple(buf, word, cond);
    }

    if (isFloatPop(word)) {
        return formatFloatStack(buf, word, cond, "vpop");
    }

    if (isFloatLoadMultiple(word)) {
        return formatFloatLoadMultiple(buf, word, cond);
    }

    if (isFloatAbs(word)) {
        return formatFloatAbs(buf, word, cond);
    }

    if (isFloatNeg(word)) {
        return formatFloatNeg(buf, word, cond);
    }

    if (isFloatSqrt(word)) {
        return formatFloatSqrt(buf, word, cond);
    }

    if (isFloatConvertWidth(word)) {
        return formatFloatConvertWidth(buf, word, cond);
    }

    if (isFloatConvertIntToFloat(word)) {
        return formatFloatConvertIntToFloat(buf, word, cond);
    }

    if (isFloatConvertToUnsigned(word)) {
        return formatFloatConvertToInt(buf, word, cond, "u32");
    }

    if (isFloatConvertToSigned(word)) {
        return formatFloatConvertToInt(buf, word, cond, "s32");
    }

    if (isFloatStatusWrite(word)) {
        return formatFloatStatusWrite(buf, word, cond);
    }

    if (isFloatStatusRead(word)) {
        return formatFloatStatusRead(buf, word, cond);
    }

    if (cond == 0xf and ((word >> 25) & 0x7) == 0x5) {
        return formatBranchExchangeImmediate(buf, word);
    }

    const branch_reg = word & 0x0ffffff0;
    if (branch_reg == 0x012fff10 or branch_reg == 0x012fff20 or branch_reg == 0x012fff30) {
        const rm = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
        const suffix = condName(cond);
        if (branch_reg == 0x012fff10) {
            return std.fmt.bufPrint(buf, "bx{} {}", .{ suffix, arm_state.regName(rm) }) catch error.NoSpaceLeft;
        }
        if (branch_reg == 0x012fff20) {
            return std.fmt.bufPrint(buf, "bxj{} {}", .{ suffix, arm_state.regName(rm) }) catch error.NoSpaceLeft;
        }
        if (branch_reg == 0x012fff30) {
            return std.fmt.bufPrint(buf, "blx{} {}", .{ suffix, arm_state.regName(rm) }) catch error.NoSpaceLeft;
        }
    }

    if (((word >> 25) & 0x7) == 0x5) {
        return formatBranchImmediate(buf, word, cond);
    }

    if ((word & 0x0f000000) == 0x0f000000) {
        const code = arm_state.conditionFromNibble(cond) orelse return error.UnknownInstruction;
        return std.fmt.bufPrint(buf, "svc{} #{}", .{
            arm_state.conditionSuffix(code),
            word & 0x00ffffff,
        }) catch error.NoSpaceLeft;
    }

    if ((word & 0xfff000f0) == 0xe7f000f0) {
        return std.fmt.bufPrint(buf, "udf", .{}) catch error.NoSpaceLeft;
    }

    if ((word & 0x0ff000f0) == 0x01200070) {
        const value = (((word >> 8) & 0xfff) << 4) | (word & 0xf);
        return std.fmt.bufPrint(buf, "bkpt #{}", .{value}) catch error.NoSpaceLeft;
    }

    if ((word & 0x0fffffff) == 0x0320f000) {
        return std.fmt.bufPrint(buf, "nop", .{}) catch error.NoSpaceLeft;
    }

    if ((word & 0xfd70f000) == 0xf550f000) {
        return std.fmt.bufPrint(buf, "pld #{x}", .{word}) catch error.NoSpaceLeft;
    }

    if ((word & 0x0fffffff) == 0x0320f004) {
        return std.fmt.bufPrint(buf, "sev", .{}) catch error.NoSpaceLeft;
    }

    if ((word & 0x0fffffff) == 0x0320f002) {
        return std.fmt.bufPrint(buf, "wfe", .{}) catch error.NoSpaceLeft;
    }

    if ((word & 0x0fffffff) == 0x0320f003) {
        return std.fmt.bufPrint(buf, "wfi", .{}) catch error.NoSpaceLeft;
    }

    if ((word & 0x0fffffff) == 0x0320f001) {
        return std.fmt.bufPrint(buf, "yield", .{}) catch error.NoSpaceLeft;
    }

    if ((word & 0xfffffdff) == 0xf1010000) {
        const name = if ((word & 0x00000200) != 0) "be" else "le";
        return std.fmt.bufPrint(buf, "setend {}", .{name}) catch error.NoSpaceLeft;
    }

    if (try formatCoprocessor(buf, word)) |text| {
        return text;
    }

    if (isStatusRead(word)) {
        return formatStatusRead(buf, word, cond);
    }

    if (isStatusWriteImmediate(word)) {
        return formatStatusWriteImmediate(buf, word, cond);
    }

    if (isStatusWriteRegister(word)) {
        return formatStatusWriteRegister(buf, word, cond);
    }

    if ((word & 0x0fff0ff0) == 0x06bf0f30) {
        return formatArmUnaryReg(buf, "rev", word, cond);
    }

    if (arm_exec.isRevHalfwords(word)) {
        return formatArmUnaryReg(buf, "rev16", word, cond);
    }

    if ((word & 0x0fff0ff0) == 0x06ff0fb0) {
        return formatArmUnaryReg(buf, "revsh", word, cond);
    }

    if (armExtendText(word)) |info| {
        return formatArmExtend(buf, word, info);
    }

    if (isSyncArmFormat(word)) {
        return formatSyncArm(buf, word, cond);
    }

    if (isMiscArmFormat(word)) {
        return formatMiscArm(buf, word, cond);
    }

    if (isSaturatingArmFormat(word)) {
        return formatSaturatingArm(buf, word, cond);
    }

    if (isParallelSaturatingFormat(word)) {
        return formatParallelSaturating(buf, word, cond);
    }

    if (isHalfMultiplyFormat(word)) {
        return formatHalfMultiply(buf, word, cond);
    }

    if (isDualMultiplyFormat(word)) {
        return formatDualMultiply(buf, word, cond);
    }

    if (isPackHalfword(word)) {
        return formatPackHalfword(buf, word, cond);
    }

    if (isSignedTopMultiply(word)) {
        return formatSignedTopMultiply(buf, word, cond);
    }

    if (arm_exec.isMultiply(word)) {
        return formatArmMultiply(buf, word);
    }

    if (isArmLoadMultiple(word)) {
        return formatArmLoadMultiple(buf, word, cond);
    }

    if (isArmStoreMultiple(word)) {
        return formatArmStoreMultiple(buf, word, cond);
    }

    if (arm_exec.isLoadWord(word)) {
        return formatArmTransferWord(buf, "ldr", word);
    }

    if (arm_exec.isLoadByte(word)) {
        return formatArmTransferWord(buf, "ldrb", word);
    }

    if (arm_exec.isLoadHalf(word)) {
        return formatArmTransferHalf(buf, "ldrh", word);
    }

    if (arm_exec.isLoadSignedByte(word)) {
        return formatArmTransferHalf(buf, "ldrsb", word);
    }

    if (arm_exec.isLoadSignedHalf(word)) {
        return formatArmTransferHalf(buf, "ldrsh", word);
    }

    if (arm_exec.isLoadDouble(word)) {
        return formatArmTransferDouble(buf, "ldrd", word);
    }

    if (arm_exec.isStoreWord(word)) {
        return formatArmTransferWord(buf, "str", word);
    }

    if (arm_exec.isStoreByte(word)) {
        return formatArmTransferWord(buf, "strb", word);
    }

    if (arm_exec.isStoreHalf(word)) {
        return formatArmTransferHalf(buf, "strh", word);
    }

    if (arm_exec.isStoreDouble(word)) {
        return formatArmTransferDouble(buf, "strd", word);
    }

    if (arm_exec.isDataProcessing(word)) {
        return formatArmData(buf, word);
    }

    return std.fmt.bufPrint(buf, "unknown #{x}", .{word}) catch error.NoSpaceLeft;
}

const ArmExtendText = struct {
    name: []const u8,
    base: bool,
};

fn formatArmExtend(buf: []u8, word: u32, info: ArmExtendText) TextError![]u8 {
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

fn isStatusRead(word: u32) bool {
    return (word & 0x0fff0fff) == 0x010f0000 and arm_state.conditionFromNibble(@intCast(u4, word >> 28)) != null;
}

fn isStatusWriteImmediate(word: u32) bool {
    return (word & 0x0ff3f000) == 0x0320f000 and arm_state.conditionFromNibble(@intCast(u4, word >> 28)) != null;
}

fn isStatusWriteRegister(word: u32) bool {
    return (word & 0x0ff3fff0) == 0x0120f000 and arm_state.conditionFromNibble(@intCast(u4, word >> 28)) != null;
}

fn formatFloatAdd(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatThree(buf: []u8, word: u32, cond: u4, name: []const u8) TextError![]u8 {
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

fn formatFloatSub(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatMul(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatNegMul(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatDiv(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatMoveCoreToPairLow(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{}.32 d{}, {}", .{
        condName(cond),
        floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
        arm_state.regName(armReg(word >> 12)),
    }) catch error.NoSpaceLeft;
}

fn formatFloatMovePairLowToCore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{}.32 {}, d{}", .{
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
    }) catch error.NoSpaceLeft;
}

fn formatFloatMoveCoreToWord(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{}.32 s{}, {}", .{
        condName(cond),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        arm_state.regName(armReg(word >> 12)),
    }) catch error.NoSpaceLeft;
}

fn formatFloatMoveWordToCore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{}.32 {}, s{}", .{
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
    }) catch error.NoSpaceLeft;
}

fn formatFloatMoveTwoCoreToTwoWord(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const first = floatWordTextIndex(word, bits.getBit32(word, 5));
    return std.fmt.bufPrint(buf, "vmov{} s{}, s{}, {}, {}", .{
        condName(cond),
        first,
        first + 1,
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
    }) catch error.NoSpaceLeft;
}

fn formatFloatMoveTwoWordToTwoCore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const first = floatWordTextIndex(word, bits.getBit32(word, 5));
    return std.fmt.bufPrint(buf, "vmov{} {}, {}, s{}, s{}", .{
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
        first,
        first + 1,
    }) catch error.NoSpaceLeft;
}

fn formatFloatMoveTwoCoreToPair(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{} d{}, {}, {}", .{
        condName(cond),
        floatPairTextIndex(word, bits.getBit32(word, 5)),
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
    }) catch error.NoSpaceLeft;
}

fn formatFloatMovePairToTwoCore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{} {}, {}, d{}", .{
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
        floatPairTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

fn formatFloatMoveReg(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatLoad(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatStore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatStack(buf: []u8, word: u32, cond: u4, name: []const u8) TextError![]u8 {
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

fn formatFloatStoreMultiple(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatLoadMultiple(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatAbs(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatNeg(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatSqrt(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatConvertWidth(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatConvertIntToFloat(buf: []u8, word: u32, cond: u4) TextError![]u8 {
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

fn formatFloatConvertToInt(buf: []u8, word: u32, cond: u4, int_type: []const u8) TextError![]u8 {
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

fn formatFloatStatusWrite(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const source = armReg(word >> 12);
    return std.fmt.bufPrint(buf, "vmsr{} fpscr, {}", .{
        condName(cond),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

fn formatFloatStatusRead(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const dest = armReg(word >> 12);
    if (dest == .pc) {
        return std.fmt.bufPrint(buf, "vmrs{} apsr_nzcv, fpscr", .{condName(cond)}) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vmrs{} {}, fpscr", .{
        condName(cond),
        arm_state.regName(dest),
    }) catch error.NoSpaceLeft;
}

fn floatWordTextIndex(value: u32, high: bool) u32 {
    return ((value & 0xf) << 1) | @as(u32, @boolToInt(high));
}

fn floatPairTextIndex(value: u32, high: bool) u32 {
    return (value & 0xf) | (@as(u32, @boolToInt(high)) << 4);
}

fn statusMaskName(word: u32) TextError![]const u8 {
    return switch ((word >> 18) & 0x3) {
        0x1 => "g",
        0x2 => "nzcvq",
        0x3 => "nzcvqg",
        else => error.UnknownInstruction,
    };
}

fn formatStatusRead(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const dest = armReg(word >> 12);
    return std.fmt.bufPrint(buf, "mrs{} {}, apsr", .{
        condName(cond),
        arm_state.regName(dest),
    }) catch error.NoSpaceLeft;
}

fn formatStatusWriteImmediate(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "msr{} apsr_{}, #{}", .{
        condName(cond),
        try statusMaskName(word),
        arm_exec.expandArmImmediate(@intCast(u8, (word >> 8) & 0xf), @intCast(u8, word & 0xff)),
    }) catch error.NoSpaceLeft;
}

fn formatStatusWriteRegister(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const source = armReg(word);
    return std.fmt.bufPrint(buf, "msr{} apsr_{}, {}", .{
        condName(cond),
        try statusMaskName(word),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

fn formatCoprocessor(buf: []u8, word: u32) TextError!?[]u8 {
    if ((word & 0xff000010) == 0xfe000010 or (word & 0x0f000010) == 0x0e000000) {
        return std.fmt.bufPrint(buf, "cdp #{x}", .{word}) catch error.NoSpaceLeft;
    }

    if ((word & 0xfe100000) == 0xfc100000 or (word & 0x0e100000) == 0x0c100000) {
        return std.fmt.bufPrint(buf, "ldc #{x}", .{word}) catch error.NoSpaceLeft;
    }

    if ((word & 0xff100010) == 0xfe000010 or (word & 0x0f100010) == 0x0e000010) {
        return std.fmt.bufPrint(buf, "mcr #{x}", .{word}) catch error.NoSpaceLeft;
    }

    if ((word & 0xfff00000) == 0xfc400000 or (word & 0x0ff00000) == 0x0c400000) {
        return std.fmt.bufPrint(buf, "mcrr #{x}", .{word}) catch error.NoSpaceLeft;
    }

    if ((word & 0xff100010) == 0xfe100010 or (word & 0x0f100010) == 0x0e100010) {
        return std.fmt.bufPrint(buf, "mrc #{x}", .{word}) catch error.NoSpaceLeft;
    }

    if ((word & 0xfff00000) == 0xfc500000 or (word & 0x0ff00000) == 0x0c500000) {
        return std.fmt.bufPrint(buf, "mrrc #{x}", .{word}) catch error.NoSpaceLeft;
    }

    if ((word & 0xfe100000) == 0xfc000000 or (word & 0x0e100000) == 0x0c000000) {
        return std.fmt.bufPrint(buf, "stc #{x}", .{word}) catch error.NoSpaceLeft;
    }

    return null;
}

fn armReg(value: u32) arm_state.ArmReg {
    return @intToEnum(arm_state.ArmReg, @intCast(u8, value & 0xf));
}

fn isArmLoadMultiple(word: u32) bool {
    return (word & 0x0e500000) == 0x08100000 and arm_state.conditionFromNibble(@intCast(u4, word >> 28)) != null;
}

fn isArmStoreMultiple(word: u32) bool {
    return (word & 0x0e500000) == 0x08000000 and arm_state.conditionFromNibble(@intCast(u4, word >> 28)) != null;
}

fn formatArmLoadMultiple(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    var used: usize = 0;
    const op = if (bits.getBit32(word, 24))
        if (bits.getBit32(word, 23)) "ldmib" else "ldmdb"
    else
        if (bits.getBit32(word, 23)) "ldm" else "ldmda";
    try appendText(buf, &used, op);
    try appendText(buf, &used, condName(cond));
    try appendText(buf, &used, " ");
    try appendText(buf, &used, arm_state.regName(armReg(word >> 16)));
    if (bits.getBit32(word, 21)) {
        try appendText(buf, &used, "!");
    }
    try appendText(buf, &used, ", {");
    try appendRegList(buf, &used, @intCast(u16, word & 0xffff));
    try appendText(buf, &used, "}");
    return buf[0..used];
}

fn formatArmStoreMultiple(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    var used: usize = 0;
    const op = if (bits.getBit32(word, 24))
        if (bits.getBit32(word, 23)) "stmib" else "stmdb"
    else
        if (bits.getBit32(word, 23)) "stm" else "stmda";
    try appendText(buf, &used, op);
    try appendText(buf, &used, condName(cond));
    try appendText(buf, &used, " ");
    try appendText(buf, &used, arm_state.regName(armReg(word >> 16)));
    if (bits.getBit32(word, 21)) {
        try appendText(buf, &used, "!");
    }
    try appendText(buf, &used, ", {");
    try appendRegList(buf, &used, @intCast(u16, word & 0xffff));
    try appendText(buf, &used, "}");
    return buf[0..used];
}

fn isSyncArmFormat(word: u32) bool {
    return word == 0xf57ff01f or
        (word & 0x0ff00fff) == 0x01900f9f or
        (word & 0x0ff00fff) == 0x01d00f9f or
        (word & 0x0ff00fff) == 0x01b00f9f or
        (word & 0x0ff00fff) == 0x01f00f9f or
        (word & 0x0ff00ff0) == 0x01800f90 or
        (word & 0x0ff00ff0) == 0x01c00f90 or
        (word & 0x0ff00ff0) == 0x01a00f90 or
        (word & 0x0ff00ff0) == 0x01e00f90 or
        (word & 0x0ff00ff0) == 0x01000090 or
        (word & 0x0ff00ff0) == 0x01400090;
}

fn formatSyncArm(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const base = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (word == 0xf57ff01f) {
        return std.fmt.bufPrint(buf, "clrex", .{}) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00fff) == 0x01900f9f) {
        return std.fmt.bufPrint(buf, "ldrex{} {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00fff) == 0x01d00f9f) {
        return std.fmt.bufPrint(buf, "ldrexb{} {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00fff) == 0x01b00f9f) {
        return std.fmt.bufPrint(buf, "ldrexd{} {}, {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(nextReg(dest)),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00fff) == 0x01f00f9f) {
        return std.fmt.bufPrint(buf, "ldrexh{} {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00ff0) == 0x01800f90) {
        return std.fmt.bufPrint(buf, "strex{} {}, {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(source),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00ff0) == 0x01c00f90) {
        return std.fmt.bufPrint(buf, "strexb{} {}, {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(source),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00ff0) == 0x01a00f90) {
        return std.fmt.bufPrint(buf, "strexd{} {}, {}, {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(source),
            arm_state.regName(nextReg(source)),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00ff0) == 0x01e00f90) {
        return std.fmt.bufPrint(buf, "strexh{} {}, {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(source),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00ff0) == 0x01000090) {
        return std.fmt.bufPrint(buf, "swp{} {}, {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(source),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "swpb{} {}, {}, [{}]", .{
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(source),
        arm_state.regName(base),
    }) catch error.NoSpaceLeft;
}

fn isMiscArmFormat(word: u32) bool {
    return (word & 0x0fff0ff0) == 0x016f0f10 or
        (word & 0x0ff00ff0) == 0x06800fb0 or
        (word & 0x0ff0f0f0) == 0x0780f010 or
        (word & 0x0ff000f0) == 0x07800010;
}

fn formatMiscArm(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const target = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const right = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 8) & 0xf));
    const left = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    if ((word & 0x0fff0ff0) == 0x016f0f10) {
        return std.fmt.bufPrint(buf, "clz{} {}, {}", .{
            condName(cond),
            arm_state.regName(target),
            arm_state.regName(left),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00ff0) == 0x06800fb0) {
        return std.fmt.bufPrint(buf, "sel{} {}, {}, {}", .{
            condName(cond),
            arm_state.regName(target),
            arm_state.regName(dest),
            arm_state.regName(left),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff0f0f0) == 0x0780f010) {
        return std.fmt.bufPrint(buf, "usad8{} {}, {}, {}", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "usad8a{} {}, {}, {}, {}", .{
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(left),
        arm_state.regName(right),
        arm_state.regName(target),
    }) catch error.NoSpaceLeft;
}

fn isSaturatingArmFormat(word: u32) bool {
    return (word & 0x0fe00030) == 0x06a00010 or
        (word & 0x0ff00ff0) == 0x06a00f30 or
        (word & 0x0fe00030) == 0x06e00010 or
        (word & 0x0ff00ff0) == 0x06e00f30;
}

fn formatSaturatingArm(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const unsigned = (word & 0x00400000) != 0;
    const half = (word & 0x00000fc0) == 0x00000f00;
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    if (half) {
        const sat = @intCast(u8, (word >> 16) & 0xf) + if (unsigned) 0 else 1;
        const op = if (unsigned) "usat16" else "ssat16";
        return std.fmt.bufPrint(buf, "{}{} {}, #{}, {}", .{
            op,
            condName(cond),
            arm_state.regName(dest),
            sat,
            arm_state.regName(source),
        }) catch error.NoSpaceLeft;
    }

    const sat = @intCast(u8, (word >> 16) & 0x1f) + if (unsigned) 0 else 1;
    const mode: u2 = if (bits.getBit32(word, 6)) 2 else 0;
    const amount = @intCast(u8, (word >> 7) & 0x1f);
    var shift_buf: [24]u8 = undefined;
    const shift = try formatPackShift(shift_buf[0..], mode, amount);
    const op = if (unsigned) "usat" else "ssat";
    return std.fmt.bufPrint(buf, "{}{} {}, #{}, {}{}", .{
        op,
        condName(cond),
        arm_state.regName(dest),
        sat,
        arm_state.regName(source),
        shift,
    }) catch error.NoSpaceLeft;
}

fn isParallelSaturatingFormat(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06600ff0 or
        (word & 0x0ff00ff0) == 0x06200ff0 or
        (word & 0x0ff00ff0) == 0x06600f90 or
        (word & 0x0ff00ff0) == 0x06200f90 or
        (word & 0x0ff00ff0) == 0x06600f70 or
        (word & 0x0ff00ff0) == 0x06200f70 or
        (word & 0x0ff00ff0) == 0x06600f10 or
        (word & 0x0ff00ff0) == 0x06200f10;
}

fn formatParallelSaturating(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const unsigned = (word & 0x00400000) != 0;
    const subtract = (word & 0x00000060) == 0x00000060;
    const half = (word & 0x00000080) == 0;
    const op = if (subtract)
        if (half) if (unsigned) "uqsub16" else "qsub16" else if (unsigned) "uqsub8" else "qsub8"
    else
        if (half) if (unsigned) "uqadd16" else "qadd16" else if (unsigned) "uqadd8" else "qadd8";
    return std.fmt.bufPrint(buf, "{}{} {}, {}, {}", .{
        op,
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
        arm_state.regName(armReg(word)),
    }) catch error.NoSpaceLeft;
}

fn isHalfMultiplyFormat(word: u32) bool {
    return (word & 0x0ff00090) == 0x01400080 or
        (word & 0x0ff00090) == 0x01000080 or
        (word & 0x0ff0f090) == 0x01600080 or
        (word & 0x0ff000b0) == 0x01200080 or
        (word & 0x0ff0f0b0) == 0x012000a0;
}

fn formatHalfMultiply(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const addend = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const right = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 8) & 0xf));
    const left = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const y = if (bits.getBit32(word, 6)) "t" else "b";
    const x = if (bits.getBit32(word, 5)) "t" else "b";
    if ((word & 0x0ff00090) == 0x01400080) {
        return std.fmt.bufPrint(buf, "smlal{}{}{} {}, {}, {}, {}", .{
            x,
            y,
            condName(cond),
            arm_state.regName(addend),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00090) == 0x01000080) {
        return std.fmt.bufPrint(buf, "smla{}{}{} {}, {}, {}, {}", .{
            x,
            y,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
            arm_state.regName(addend),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff0f090) == 0x01600080) {
        return std.fmt.bufPrint(buf, "smul{}{}{} {}, {}, {}", .{
            x,
            y,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff000b0) == 0x01200080) {
        return std.fmt.bufPrint(buf, "smlaw{}{} {}, {}, {}, {}", .{
            y,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
            arm_state.regName(addend),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "smulw{}{} {}, {}, {}", .{
        y,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(left),
        arm_state.regName(right),
    }) catch error.NoSpaceLeft;
}

fn isDualMultiplyFormat(word: u32) bool {
    return (word & 0x0ff000d0) == 0x07000010 or
        (word & 0x0ff000d0) == 0x07400010 or
        (word & 0x0ff000d0) == 0x07000050 or
        (word & 0x0ff000d0) == 0x07400050 or
        (word & 0x0ff0f0d0) == 0x0700f010 or
        (word & 0x0ff0f0d0) == 0x0700f050;
}

fn formatDualMultiply(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const addend = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const right = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 8) & 0xf));
    const left = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const exchange = if (bits.getBit32(word, 5)) "x" else "";
    if ((word & 0x0ff000d0) == 0x07400010) {
        return std.fmt.bufPrint(buf, "smlald{}{} {}, {}, {}, {}", .{
            exchange,
            condName(cond),
            arm_state.regName(addend),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff000d0) == 0x07400050) {
        return std.fmt.bufPrint(buf, "smlsld{}{} {}, {}, {}, {}", .{
            exchange,
            condName(cond),
            arm_state.regName(addend),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff0f0d0) == 0x0700f010) {
        return std.fmt.bufPrint(buf, "smuad{}{} {}, {}, {}", .{
            exchange,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff0f0d0) == 0x0700f050) {
        return std.fmt.bufPrint(buf, "smusd{}{} {}, {}, {}", .{
            exchange,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }

    const op = if ((word & 0x0ff000d0) == 0x07000050) "smlsd" else "smlad";
    return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}, {}", .{
        op,
        exchange,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(left),
        arm_state.regName(right),
        arm_state.regName(addend),
    }) catch error.NoSpaceLeft;
}

fn isPackHalfword(word: u32) bool {
    return (word & 0x0ff00070) == 0x06800010 or (word & 0x0ff00070) == 0x06800050;
}

fn formatPackHalfword(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const top = (word & 0x0ff00070) == 0x06800050;
    const op = if (top) "pkhtb" else "pkhbt";
    const mode: u2 = if (top) 2 else 0;
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const base = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const amount = @intCast(u8, (word >> 7) & 0x1f);
    var shift_buf: [24]u8 = undefined;
    const shift = try formatPackShift(shift_buf[0..], mode, amount);
    return std.fmt.bufPrint(buf, "{}{} {}, {}, {}{}", .{
        op,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(base),
        arm_state.regName(source),
        shift,
    }) catch error.NoSpaceLeft;
}

fn formatPackShift(buf: []u8, mode: u2, amount: u8) TextError![]u8 {
    if (mode == 0 and amount == 0) {
        return buf[0..0];
    }
    if (mode == 2 and amount == 0) {
        return std.fmt.bufPrint(buf, ", asr #32", .{}) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, ", {} #{}", .{ shiftName(mode), amount }) catch error.NoSpaceLeft;
}

fn isSignedTopMultiply(word: u32) bool {
    return (word & 0x0ff0f0d0) == 0x0750f010 or
        (word & 0x0ff000d0) == 0x07500010 or
        (word & 0x0ff000d0) == 0x075000d0;
}

fn formatSignedTopMultiply(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const rounded = if (bits.getBit32(word, 5)) "r" else "";
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const left = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const right = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 8) & 0xf));
    if ((word & 0x0ff0f0d0) == 0x0750f010) {
        return std.fmt.bufPrint(buf, "smmul{}{} {}, {}, {}", .{
            rounded,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }

    const addend = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const op = if ((word & 0x0ff000d0) == 0x075000d0) "smmls" else "smmla";
    return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}, {}", .{
        op,
        rounded,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(left),
        arm_state.regName(right),
        arm_state.regName(addend),
    }) catch error.NoSpaceLeft;
}

fn formatExtendSource(buf: []u8, word: u32) TextError![]u8 {
    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const rotate = @intCast(u8, ((word >> 10) & 0x3) * 8);
    if (rotate == 0) {
        return std.fmt.bufPrint(buf, "{}", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}, ror #{}", .{ arm_state.regName(source), rotate }) catch error.NoSpaceLeft;
}

fn armExtendText(word: u32) ?ArmExtendText {
    if (arm_state.conditionFromNibble(@intCast(u4, word >> 28)) == null) {
        return null;
    }
    if ((word & 0x0fff03f0) == 0x068f0070) {
        return ArmExtendText{ .name = "sxtb16", .base = false };
    }
    if ((word & 0x0fff03f0) == 0x06af0070) {
        return ArmExtendText{ .name = "sxtb", .base = false };
    }
    if ((word & 0x0fff03f0) == 0x06bf0070) {
        return ArmExtendText{ .name = "sxth", .base = false };
    }
    if ((word & 0x0fff03f0) == 0x06cf0070) {
        return ArmExtendText{ .name = "uxtb16", .base = false };
    }
    if ((word & 0x0fff03f0) == 0x06ef0070) {
        return ArmExtendText{ .name = "uxtb", .base = false };
    }
    if ((word & 0x0fff03f0) == 0x06ff0070) {
        return ArmExtendText{ .name = "uxth", .base = false };
    }
    if ((word & 0x0ff003f0) == 0x06800070) {
        return ArmExtendText{ .name = "sxtab16", .base = true };
    }
    if ((word & 0x0ff003f0) == 0x06a00070) {
        return ArmExtendText{ .name = "sxtab", .base = true };
    }
    if ((word & 0x0ff003f0) == 0x06b00070) {
        return ArmExtendText{ .name = "sxtah", .base = true };
    }
    if ((word & 0x0ff003f0) == 0x06c00070) {
        return ArmExtendText{ .name = "uxtab16", .base = true };
    }
    if ((word & 0x0ff003f0) == 0x06e00070) {
        return ArmExtendText{ .name = "uxtab", .base = true };
    }
    if ((word & 0x0ff003f0) == 0x06f00070) {
        return ArmExtendText{ .name = "uxtah", .base = true };
    }
    return null;
}

const MultiplyText = struct {
    name: []const u8,
    long: bool,
    addend: bool,
    flags: bool,
};

fn formatArmMultiply(buf: []u8, word: u32) TextError![]u8 {
    const info = multiplyText(word) orelse return error.UnknownInstruction;
    const cond = @intCast(u4, word >> 28);
    const flags = if (info.flags and bits.getBit32(word, 20)) "s" else "";
    const dest_hi = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const dest_lo = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const right = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 8) & 0xf));
    const left = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));

    if (info.long) {
        return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}, {}", .{
            info.name,
            condName(cond),
            flags,
            arm_state.regName(dest_lo),
            arm_state.regName(dest_hi),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }

    if (info.addend) {
        return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}, {}", .{
            info.name,
            condName(cond),
            flags,
            arm_state.regName(dest_hi),
            arm_state.regName(left),
            arm_state.regName(right),
            arm_state.regName(dest_lo),
        }) catch error.NoSpaceLeft;
    }

    return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}", .{
        info.name,
        condName(cond),
        flags,
        arm_state.regName(dest_hi),
        arm_state.regName(left),
        arm_state.regName(right),
    }) catch error.NoSpaceLeft;
}

fn multiplyText(word: u32) ?MultiplyText {
    if (arm_state.conditionFromNibble(@intCast(u4, word >> 28)) == null) {
        return null;
    }
    if ((word & 0x0fe0f0f0) == 0x00000090) {
        return MultiplyText{ .name = "mul", .long = false, .addend = false, .flags = true };
    }
    if ((word & 0x0fe000f0) == 0x00200090) {
        return MultiplyText{ .name = "mla", .long = false, .addend = true, .flags = true };
    }
    if ((word & 0x0fe000f0) == 0x00800090) {
        return MultiplyText{ .name = "umull", .long = true, .addend = false, .flags = true };
    }
    if ((word & 0x0fe000f0) == 0x00a00090) {
        return MultiplyText{ .name = "umlal", .long = true, .addend = false, .flags = true };
    }
    if ((word & 0x0ff000f0) == 0x00400090) {
        return MultiplyText{ .name = "umaal", .long = true, .addend = false, .flags = false };
    }
    if ((word & 0x0fe000f0) == 0x00c00090) {
        return MultiplyText{ .name = "smull", .long = true, .addend = false, .flags = true };
    }
    if ((word & 0x0fe000f0) == 0x00e00090) {
        return MultiplyText{ .name = "smlal", .long = true, .addend = false, .flags = true };
    }
    return null;
}

fn formatArmTransferWord(buf: []u8, comptime op: []const u8, word: u32) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    const pre_index = bits.getBit32(word, 24);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const base = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const bang: []const u8 = if (writeback) "!" else "";
    var offset_buf: [48]u8 = undefined;
    const offset = try formatArmLoadOffset(offset_buf[0..], word);

    if (pre_index) {
        if (offset.len == 0) {
            return std.fmt.bufPrint(buf, "{}{} {}, [{}]{}", .{
                op,
                condName(cond),
                arm_state.regName(dest),
                arm_state.regName(base),
                bang,
            }) catch error.NoSpaceLeft;
        }
        return std.fmt.bufPrint(buf, "{}{} {}, [{}, {}]{}", .{
            op,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
            offset,
            bang,
        }) catch error.NoSpaceLeft;
    }

    if (offset.len == 0) {
        return std.fmt.bufPrint(buf, "{}{} {}, [{}], #0", .{
            op,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{} {}, [{}], {}", .{
        op,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(base),
        offset,
    }) catch error.NoSpaceLeft;
}

fn formatArmLoadOffset(buf: []u8, word: u32) TextError![]u8 {
    const increase = bits.getBit32(word, 23);
    if (!bits.getBit32(word, 25)) {
        const offset = word & 0xfff;
        if (offset == 0) {
            return buf[0..0];
        }
        if (increase) {
            return std.fmt.bufPrint(buf, "#+{}", .{offset}) catch error.NoSpaceLeft;
        }
        return std.fmt.bufPrint(buf, "#-{}", .{offset}) catch error.NoSpaceLeft;
    }

    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const mode = @intCast(u2, (word >> 5) & 0x3);
    const amount = @intCast(u8, (word >> 7) & 0x1f);
    const prefix: []const u8 = if (increase) "+" else "-";
    if (mode == 0 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}{}", .{ prefix, arm_state.regName(source) }) catch error.NoSpaceLeft;
    }
    if (mode == 1 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}{}, lsr #32", .{ prefix, arm_state.regName(source) }) catch error.NoSpaceLeft;
    }
    if (mode == 2 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}{}, asr #32", .{ prefix, arm_state.regName(source) }) catch error.NoSpaceLeft;
    }
    if (mode == 3 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}{}, rrx", .{ prefix, arm_state.regName(source) }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{}, {} #{}", .{
        prefix,
        arm_state.regName(source),
        shiftName(mode),
        amount,
    }) catch error.NoSpaceLeft;
}

fn formatArmTransferHalf(buf: []u8, comptime op: []const u8, word: u32) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    const pre_index = bits.getBit32(word, 24);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const base = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const bang: []const u8 = if (writeback) "!" else "";
    var offset_buf: [48]u8 = undefined;
    const offset = try formatArmHalfOffset(offset_buf[0..], word);

    if (pre_index) {
        if (offset.len == 0) {
            return std.fmt.bufPrint(buf, "{}{} {}, [{}]{}", .{
                op,
                condName(cond),
                arm_state.regName(dest),
                arm_state.regName(base),
                bang,
            }) catch error.NoSpaceLeft;
        }
        return std.fmt.bufPrint(buf, "{}{} {}, [{}, {}]{}", .{
            op,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
            offset,
            bang,
        }) catch error.NoSpaceLeft;
    }

    if (offset.len == 0) {
        return std.fmt.bufPrint(buf, "{}{} {}, [{}], #0", .{
            op,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{} {}, [{}], {}", .{
        op,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(base),
        offset,
    }) catch error.NoSpaceLeft;
}

fn formatArmHalfOffset(buf: []u8, word: u32) TextError![]u8 {
    const increase = bits.getBit32(word, 23);
    if (bits.getBit32(word, 22)) {
        const offset = ((word >> 4) & 0xf0) | (word & 0xf);
        if (offset == 0) {
            return buf[0..0];
        }
        if (increase) {
            return std.fmt.bufPrint(buf, "#+{}", .{offset}) catch error.NoSpaceLeft;
        }
        return std.fmt.bufPrint(buf, "#-{}", .{offset}) catch error.NoSpaceLeft;
    }

    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    if (increase) {
        return std.fmt.bufPrint(buf, "+{}", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "-{}", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
}

fn formatArmTransferDouble(buf: []u8, comptime op: []const u8, word: u32) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    const pre_index = bits.getBit32(word, 24);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const first = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const base = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const bang: []const u8 = if (writeback) "!" else "";
    var offset_buf: [48]u8 = undefined;
    const offset = try formatArmHalfOffset(offset_buf[0..], word);

    if (pre_index) {
        if (offset.len == 0) {
            return std.fmt.bufPrint(buf, "{}{} {}, {}, [{}]{}", .{
                op,
                condName(cond),
                arm_state.regName(first),
                arm_state.regName(nextReg(first)),
                arm_state.regName(base),
                bang,
            }) catch error.NoSpaceLeft;
        }
        return std.fmt.bufPrint(buf, "{}{} {}, {}, [{}, {}]{}", .{
            op,
            condName(cond),
            arm_state.regName(first),
            arm_state.regName(nextReg(first)),
            arm_state.regName(base),
            offset,
            bang,
        }) catch error.NoSpaceLeft;
    }

    if (offset.len == 0) {
        return std.fmt.bufPrint(buf, "{}{} {}, {}, [{}], #0", .{
            op,
            condName(cond),
            arm_state.regName(first),
            arm_state.regName(nextReg(first)),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{} {}, {}, [{}], {}", .{
        op,
        condName(cond),
        arm_state.regName(first),
        arm_state.regName(nextReg(first)),
        arm_state.regName(base),
        offset,
    }) catch error.NoSpaceLeft;
}

fn nextReg(reg: arm_state.ArmReg) arm_state.ArmReg {
    const next = @enumToInt(reg) + 1;
    if (next >= 15) {
        return .pc;
    }
    return @intToEnum(arm_state.ArmReg, @intCast(u8, next));
}

fn formatArmData(buf: []u8, word: u32) TextError![]u8 {
    const op = @intCast(u4, (word >> 21) & 0xf);
    const name = dataName(op) orelse return error.UnknownInstruction;
    const cond = @intCast(u4, word >> 28);
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const base = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    var rhs_buf: [48]u8 = undefined;
    const rhs = try formatArmOperand2(rhs_buf[0..], word);

    if (op >= 0x8 and op <= 0xb) {
        return std.fmt.bufPrint(buf, "{}{} {}, {}", .{
            name,
            condName(cond),
            arm_state.regName(base),
            rhs,
        }) catch error.NoSpaceLeft;
    }

    const flags = if (bits.getBit32(word, 20)) "s" else "";
    if (op == 0xd or op == 0xf) {
        return std.fmt.bufPrint(buf, "{}{}{} {}, {}", .{
            name,
            condName(cond),
            flags,
            arm_state.regName(dest),
            rhs,
        }) catch error.NoSpaceLeft;
    }

    return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}", .{
        name,
        condName(cond),
        flags,
        arm_state.regName(dest),
        arm_state.regName(base),
        rhs,
    }) catch error.NoSpaceLeft;
}

fn formatArmOperand2(buf: []u8, word: u32) TextError![]u8 {
    if (bits.getBit32(word, 25)) {
        const rotate = @intCast(u8, (word >> 8) & 0xf);
        const imm = @intCast(u8, word & 0xff);
        return std.fmt.bufPrint(buf, "#{}", .{arm_exec.expandArmImmediate(rotate, imm)}) catch error.NoSpaceLeft;
    }

    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const mode = @intCast(u2, (word >> 5) & 0x3);
    if (bits.getBit32(word, 4)) {
        const amount = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 8) & 0xf));
        return std.fmt.bufPrint(buf, "{}, {} {}", .{
            arm_state.regName(source),
            shiftName(mode),
            arm_state.regName(amount),
        }) catch error.NoSpaceLeft;
    }

    const amount = @intCast(u8, (word >> 7) & 0x1f);
    if (mode == 0 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    if (mode == 1 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}, lsr #32", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    if (mode == 2 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}, asr #32", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    if (mode == 3 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}, rrx", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}, {} #{}", .{
        arm_state.regName(source),
        shiftName(mode),
        amount,
    }) catch error.NoSpaceLeft;
}

fn dataName(op: u4) ?[]const u8 {
    return switch (op) {
        0x0 => "and",
        0x1 => "eor",
        0x2 => "sub",
        0x3 => "rsb",
        0x4 => "add",
        0x5 => "adc",
        0x6 => "sbc",
        0x7 => "rsc",
        0x8 => "tst",
        0x9 => "teq",
        0xa => "cmp",
        0xb => "cmn",
        0xc => "orr",
        0xd => "mov",
        0xe => "bic",
        0xf => "mvn",
    };
}

fn shiftName(mode: u2) []const u8 {
    return switch (mode) {
        0 => "lsl",
        1 => "lsr",
        2 => "asr",
        3 => "ror",
    };
}

fn formatArmUnaryReg(buf: []u8, comptime op: []const u8, word: u32, cond: u4) TextError![]u8 {
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    return std.fmt.bufPrint(buf, "{}{} {}, {}", .{
        op,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

pub fn formatThumb16(buf: []u8, word: u16) TextError![]u8 {
    if ((word & 0xf800) == 0x0000) {
        return formatThumbShiftImm(buf, "lsls", word, false);
    }
    if ((word & 0xf800) == 0x0800) {
        return formatThumbShiftImm(buf, "lsrs", word, true);
    }
    if ((word & 0xf800) == 0x1000) {
        return formatThumbShiftImm(buf, "asrs", word, true);
    }
    if ((word & 0xfe00) == 0x1800) {
        const addend = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "adds {}, {}, {}", .{
            arm_state.regName(dest),
            arm_state.regName(base),
            arm_state.regName(addend),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xfe00) == 0x1a00) {
        const subtrahend = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "subs {}, {}, {}", .{
            arm_state.regName(dest),
            arm_state.regName(base),
            arm_state.regName(subtrahend),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xfe00) == 0x1c00) {
        const amount = @intCast(u8, (word >> 6) & 7);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "adds {}, {}, #{}", .{
            arm_state.regName(dest),
            arm_state.regName(base),
            amount,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xfe00) == 0x1e00) {
        const amount = @intCast(u8, (word >> 6) & 7);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "subs {}, {}, #{}", .{
            arm_state.regName(dest),
            arm_state.regName(base),
            amount,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x2000) {
        const dest = arm_state.lowReg(word >> 8);
        const imm = @intCast(u8, word & 0xff);
        return std.fmt.bufPrint(buf, "movs {}, #{}", .{
            arm_state.regName(dest),
            imm,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x2800) {
        const source = arm_state.lowReg(word >> 8);
        const imm = @intCast(u8, word & 0xff);
        return std.fmt.bufPrint(buf, "cmp {}, #{}", .{
            arm_state.regName(source),
            imm,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x3000) {
        const dest = arm_state.lowReg(word >> 8);
        const imm = @intCast(u8, word & 0xff);
        return std.fmt.bufPrint(buf, "adds {}, #{}", .{
            arm_state.regName(dest),
            imm,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x3800) {
        const dest = arm_state.lowReg(word >> 8);
        const imm = @intCast(u8, word & 0xff);
        return std.fmt.bufPrint(buf, "subs {}, #{}", .{
            arm_state.regName(dest),
            imm,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xffc0) == 0x4000) {
        return formatThumbBitReg(buf, "ands", word);
    }
    if ((word & 0xffc0) == 0x4040) {
        return formatThumbBitReg(buf, "eors", word);
    }
    if ((word & 0xffc0) == 0x4080) {
        return formatThumbShiftReg(buf, "lsls", word);
    }
    if ((word & 0xffc0) == 0x40c0) {
        return formatThumbShiftReg(buf, "lsrs", word);
    }
    if ((word & 0xffc0) == 0x4100) {
        return formatThumbShiftReg(buf, "asrs", word);
    }
    if ((word & 0xffc0) == 0x4140) {
        return formatThumbBitReg(buf, "adcs", word);
    }
    if ((word & 0xffc0) == 0x4180) {
        return formatThumbBitReg(buf, "sbcs", word);
    }
    if ((word & 0xffc0) == 0x41c0) {
        return formatThumbBitReg(buf, "rors", word);
    }
    if ((word & 0xffc0) == 0x4200) {
        return formatThumbBitReg(buf, "tst", word);
    }
    if ((word & 0xffc0) == 0x4240) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "rsbs {}, {}, #0", .{
            arm_state.regName(dest),
            arm_state.regName(source),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xffc0) == 0x4280) {
        return formatThumbBitReg(buf, "cmp", word);
    }
    if ((word & 0xffc0) == 0x42c0) {
        return formatThumbBitReg(buf, "cmn", word);
    }
    if ((word & 0xffc0) == 0x4300) {
        return formatThumbBitReg(buf, "orrs", word);
    }
    if ((word & 0xffc0) == 0x4380) {
        return formatThumbBitReg(buf, "bics", word);
    }
    if ((word & 0xffc0) == 0x43c0) {
        return formatThumbBitReg(buf, "mvns", word);
    }
    if ((word & 0xff00) == 0x4400) {
        const dest = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const addend = arm_state.reg4(word >> 3);
        return std.fmt.bufPrint(buf, "add {}, {}", .{
            arm_state.regName(dest),
            arm_state.regName(addend),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xff00) == 0x4500) {
        const left = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const right = arm_state.reg4(word >> 3);
        return std.fmt.bufPrint(buf, "cmp {}, {}", .{
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xff00) == 0x4600) {
        const dest = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const source = arm_state.reg4(word >> 3);
        return std.fmt.bufPrint(buf, "mov {}, {}", .{
            arm_state.regName(dest),
            arm_state.regName(source),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xff87) == 0x4700) {
        const source = arm_state.reg4(word >> 3);
        return std.fmt.bufPrint(buf, "bx {}", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    if ((word & 0xff87) == 0x4780) {
        const source = arm_state.reg4(word >> 3);
        return std.fmt.bufPrint(buf, "blx {}", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x4800) {
        const dest = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        return std.fmt.bufPrint(buf, "ldr {}, [pc, #{}]", .{
            arm_state.regName(dest),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xfe00) == 0x5000) {
        return formatThumbTransferReg(buf, "str", word);
    }
    if ((word & 0xfe00) == 0x5200) {
        return formatThumbTransferReg(buf, "strh", word);
    }
    if ((word & 0xfe00) == 0x5400) {
        return formatThumbTransferReg(buf, "strb", word);
    }
    if ((word & 0xfe00) == 0x5600) {
        return formatThumbTransferReg(buf, "ldrsb", word);
    }
    if ((word & 0xfe00) == 0x5800) {
        return formatThumbTransferReg(buf, "ldr", word);
    }
    if ((word & 0xfe00) == 0x5a00) {
        return formatThumbTransferReg(buf, "ldrh", word);
    }
    if ((word & 0xfe00) == 0x5c00) {
        return formatThumbTransferReg(buf, "ldrb", word);
    }
    if ((word & 0xfe00) == 0x5e00) {
        return formatThumbTransferReg(buf, "ldrsh", word);
    }
    if ((word & 0xf800) == 0x6000) {
        return formatThumbTransferImm(buf, "str", word, 2);
    }
    if ((word & 0xf800) == 0x6800) {
        const offset = @as(u32, (word >> 6) & 0x1f) << 2;
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "ldr {}, [{}, #{}]", .{
            arm_state.regName(dest),
            arm_state.regName(base),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x7000) {
        return formatThumbTransferImm(buf, "strb", word, 0);
    }
    if ((word & 0xf800) == 0x7800) {
        return formatThumbTransferImm(buf, "ldrb", word, 0);
    }
    if ((word & 0xf800) == 0x8000) {
        const offset = @as(u32, (word >> 6) & 0x1f) << 1;
        const base = arm_state.lowReg(word >> 3);
        const data = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "strh {}, [{}, #{}]", .{
            arm_state.regName(data),
            arm_state.regName(base),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x8800) {
        const offset = @as(u32, (word >> 6) & 0x1f) << 1;
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "ldrh {}, [{}, #{}]", .{
            arm_state.regName(dest),
            arm_state.regName(base),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x9000) {
        const data = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        return std.fmt.bufPrint(buf, "str {}, [sp, #{}]", .{
            arm_state.regName(data),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x9800) {
        const dest = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        return std.fmt.bufPrint(buf, "ldr {}, [sp, #{}]", .{
            arm_state.regName(dest),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0xa000) {
        const dest = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        return std.fmt.bufPrint(buf, "adr {}, +#{}", .{
            arm_state.regName(dest),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0xa800) {
        const dest = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        return std.fmt.bufPrint(buf, "add {}, sp, #{}", .{
            arm_state.regName(dest),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xff80) == 0xb000) {
        const offset = @as(u32, word & 0x7f) << 2;
        return std.fmt.bufPrint(buf, "add sp, sp, #{}", .{offset}) catch error.NoSpaceLeft;
    }
    if ((word & 0xff80) == 0xb080) {
        const offset = @as(u32, word & 0x7f) << 2;
        return std.fmt.bufPrint(buf, "sub sp, sp, #{}", .{offset}) catch error.NoSpaceLeft;
    }
    if ((word & 0xfe00) == 0xb400) {
        return formatThumbPush(buf, word);
    }
    if ((word & 0xfe00) == 0xbc00) {
        return formatThumbPop(buf, word);
    }
    if ((word & 0xfff7) == 0xb650) {
        const name = if ((word & 8) != 0) "be" else "le";
        return std.fmt.bufPrint(buf, "setend {}", .{name}) catch error.NoSpaceLeft;
    }
    if ((word & 0xffc0) == 0xb200) {
        return formatThumbUnaryReg(buf, "sxth", word);
    }
    if ((word & 0xffc0) == 0xb240) {
        return formatThumbUnaryReg(buf, "sxtb", word);
    }
    if ((word & 0xffc0) == 0xb280) {
        return formatThumbUnaryReg(buf, "uxth", word);
    }
    if ((word & 0xffc0) == 0xb2c0) {
        return formatThumbUnaryReg(buf, "uxtb", word);
    }
    if ((word & 0xffc0) == 0xba00) {
        return formatThumbUnaryReg(buf, "rev", word);
    }
    if ((word & 0xffc0) == 0xba40) {
        return formatThumbUnaryReg(buf, "rev16", word);
    }
    if ((word & 0xffc0) == 0xbac0) {
        return formatThumbUnaryReg(buf, "revsh", word);
    }
    if ((word & 0xf800) == 0xc000) {
        const base = arm_state.lowReg(word >> 8);
        return formatThumbMultiple(buf, "stm", base, @intCast(u8, word & 0xff), true);
    }
    if ((word & 0xf800) == 0xc800) {
        const base = arm_state.lowReg(word >> 8);
        const mask = @intCast(u8, word & 0xff);
        const write_back = (mask & (@as(u8, 1) << @intCast(u3, @enumToInt(base)))) == 0;
        return formatThumbMultiple(buf, "ldm", base, mask, write_back);
    }
    if ((word & 0xff00) == 0xde00) {
        return std.fmt.bufPrint(buf, "udf", .{}) catch error.NoSpaceLeft;
    }
    if ((word & 0xff00) == 0xdf00) {
        return std.fmt.bufPrint(buf, "svc #{}", .{word & 0xff}) catch error.NoSpaceLeft;
    }
    if ((word & 0xf000) == 0xd000 and (word & 0x0f00) < 0x0e00) {
        const code = arm_state.conditionFromNibble(@intCast(u4, (word >> 8) & 0xf)).?;
        const offset = bits.signExtend32(@as(u32, word & 0xff) << 1, 9) + 4;
        return std.fmt.bufPrint(buf, "b{} {c}#{}", .{
            arm_state.conditionSuffix(code),
            signChar(offset),
            abs32(offset),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0xe000) {
        const offset = bits.signExtend32(@as(u32, word & 0x7ff) << 1, 12) + 4;
        return std.fmt.bufPrint(buf, "b {c}#{}", .{
            signChar(offset),
            abs32(offset),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "unknown #{x}", .{word}) catch error.NoSpaceLeft;
}

pub fn formatThumb32(buf: []u8, word: u32) TextError![]u8 {
    const first = @intCast(u16, word & 0xffff);
    const second = @intCast(u16, (word >> 16) & 0xffff);
    if ((first & 0xf800) == 0xf000 and (second & 0xf800) == 0xf800) {
        const offset = thumb32Offset(word) + 4;
        return std.fmt.bufPrint(buf, "bl {c}#{}", .{
            signChar(offset),
            abs32(offset),
        }) catch error.NoSpaceLeft;
    }
    if ((first & 0xf800) == 0xf000 and (second & 0xf800) == 0xe800 and (second & 1) == 0) {
        const offset = thumb32Offset(word) + 4;
        return std.fmt.bufPrint(buf, "blx {c}#{}", .{
            signChar(offset),
            abs32(offset),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "unknown #{x}", .{word}) catch error.NoSpaceLeft;
}

fn formatThumbShiftImm(buf: []u8, comptime op: []const u8, word: u16, zero_is_thirty_two: bool) TextError![]u8 {
    const raw_amount = @intCast(u8, (word >> 6) & 0x1f);
    const amount = if (zero_is_thirty_two and raw_amount == 0) 32 else raw_amount;
    const source = arm_state.lowReg(word >> 3);
    const dest = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, {}, #{}", .{
        op,
        arm_state.regName(dest),
        arm_state.regName(source),
        amount,
    }) catch error.NoSpaceLeft;
}

fn formatThumbBitReg(buf: []u8, comptime op: []const u8, word: u16) TextError![]u8 {
    const source = arm_state.lowReg(word >> 3);
    const dest = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, {}", .{
        op,
        arm_state.regName(dest),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

fn formatThumbShiftReg(buf: []u8, comptime op: []const u8, word: u16) TextError![]u8 {
    const source = arm_state.lowReg(word >> 3);
    const dest = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, {}", .{
        op,
        arm_state.regName(dest),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

fn formatThumbTransferReg(buf: []u8, comptime op: []const u8, word: u16) TextError![]u8 {
    const offset = arm_state.lowReg(word >> 6);
    const base = arm_state.lowReg(word >> 3);
    const data = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, [{}, {}]", .{
        op,
        arm_state.regName(data),
        arm_state.regName(base),
        arm_state.regName(offset),
    }) catch error.NoSpaceLeft;
}

fn formatThumbTransferImm(buf: []u8, comptime op: []const u8, word: u16, comptime scale: u5) TextError![]u8 {
    const offset = @as(u32, (word >> 6) & 0x1f) << scale;
    const base = arm_state.lowReg(word >> 3);
    const data = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, [{}, #{}]", .{
        op,
        arm_state.regName(data),
        arm_state.regName(base),
        offset,
    }) catch error.NoSpaceLeft;
}

fn formatThumbUnaryReg(buf: []u8, comptime op: []const u8, word: u16) TextError![]u8 {
    const source = arm_state.lowReg(word >> 3);
    const dest = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, {}", .{
        op,
        arm_state.regName(dest),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

fn formatThumbPush(buf: []u8, word: u16) TextError![]u8 {
    var used: usize = 0;
    try appendText(buf, &used, "push {");
    var first = true;
    var index: u8 = 0;
    while (index < 8) : (index += 1) {
        if ((word & (@as(u16, 1) << @intCast(u4, index))) != 0) {
            if (!first) {
                try appendText(buf, &used, ", ");
            }
            try appendText(buf, &used, arm_state.regName(@intToEnum(arm_state.ArmReg, index)));
            first = false;
        }
    }
    if ((word & 0x0100) != 0) {
        if (!first) {
            try appendText(buf, &used, ", ");
        }
        try appendText(buf, &used, arm_state.regName(.lr));
    }
    try appendText(buf, &used, "}");
    return buf[0..used];
}

fn formatThumbPop(buf: []u8, word: u16) TextError![]u8 {
    var used: usize = 0;
    try appendText(buf, &used, "pop {");
    var first = true;
    var index: u8 = 0;
    while (index < 8) : (index += 1) {
        if ((word & (@as(u16, 1) << @intCast(u4, index))) != 0) {
            if (!first) {
                try appendText(buf, &used, ", ");
            }
            try appendText(buf, &used, arm_state.regName(@intToEnum(arm_state.ArmReg, index)));
            first = false;
        }
    }
    if ((word & 0x0100) != 0) {
        if (!first) {
            try appendText(buf, &used, ", ");
        }
        try appendText(buf, &used, arm_state.regName(.pc));
    }
    try appendText(buf, &used, "}");
    return buf[0..used];
}

fn formatThumbMultiple(buf: []u8, comptime op: []const u8, base: arm_state.ArmReg, mask: u8, write_back: bool) TextError![]u8 {
    var used: usize = 0;
    try appendText(buf, &used, op);
    try appendText(buf, &used, " ");
    try appendText(buf, &used, arm_state.regName(base));
    if (write_back) {
        try appendText(buf, &used, "!");
    }
    try appendText(buf, &used, ", {");
    try appendRegList(buf, &used, mask);
    try appendText(buf, &used, "}");
    return buf[0..used];
}

fn appendRegList(buf: []u8, used: *usize, mask: u16) TextError!void {
    var first = true;
    var index: u5 = 0;
    while (index < 16) : (index += 1) {
        if ((mask & (@as(u16, 1) << index)) != 0) {
            if (!first) {
                try appendText(buf, used, ", ");
            }
            try appendText(buf, used, arm_state.regName(@intToEnum(arm_state.ArmReg, @intCast(u8, index))));
            first = false;
        }
    }
}

fn appendText(buf: []u8, used: *usize, text: []const u8) TextError!void {
    if (used.* + text.len > buf.len) {
        return error.NoSpaceLeft;
    }
    std.mem.copy(u8, buf[used.* .. used.* + text.len], text);
    used.* += text.len;
}

fn formatBranchImmediate(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const link = bits.getBit32(word, 24);
    const imm = word & 0x00ffffff;
    const offset = bits.signExtend32(imm << 2, 26) + 8;
    const op: []const u8 = if (link) "bl" else "b";
    return std.fmt.bufPrint(buf, "{}{} {c}#{}", .{
        op,
        condName(cond),
        signChar(offset),
        abs32(offset),
    }) catch error.NoSpaceLeft;
}

fn formatBranchExchangeImmediate(buf: []u8, word: u32) TextError![]u8 {
    const high = @as(u32, @boolToInt(bits.getBit32(word, 24)));
    const imm = word & 0x00ffffff;
    const offset = bits.signExtend32((imm << 2) | (high << 1), 26) + 8;
    return std.fmt.bufPrint(buf, "blx {c}#{}", .{ signChar(offset), abs32(offset) }) catch error.NoSpaceLeft;
}

fn thumb32Offset(word: u32) i32 {
    const first = word & 0x07ff;
    const second = (word >> 16) & 0x07ff;
    return bits.signExtend32((first << 12) | (second << 1), 23);
}

fn condName(cond: u4) []const u8 {
    if (arm_state.conditionFromNibble(cond)) |code| {
        return arm_state.conditionSuffix(code);
    }
    return "";
}

fn signChar(value: i32) u8 {
    if (value < 0) {
        return '-';
    }
    return '+';
}

fn abs32(value: i32) u32 {
    if (value < 0) {
        return @intCast(u32, -value);
    }
    return @intCast(u32, value);
}
