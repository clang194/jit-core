const std = @import("std");
const bits = @import("bits.zig");
const arm_exec = @import("arm_exec.zig");
const arm_state = @import("arm_state.zig");
usingnamespace @import("arm_text_types.zig");
usingnamespace @import("arm_text_float_format.zig");
usingnamespace @import("arm_text_coprocessor_format.zig");
usingnamespace @import("arm_text_block_format.zig");
usingnamespace @import("arm_text_misc_format.zig");
usingnamespace @import("arm_text_divide_format.zig");
usingnamespace @import("arm_text_parallel_format.zig");
usingnamespace @import("arm_text_multiply_format.zig");
usingnamespace @import("arm_text_transfer_format.zig");
usingnamespace @import("arm_text_data_format.zig");
usingnamespace @import("arm_text_thumb_format.zig");
usingnamespace @import("arm_text_thumb32_format.zig");
usingnamespace @import("arm_text_common_format.zig");

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

    if (isFloatCompare(word)) {
        return formatFloatCompare(buf, word, cond);
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
        return std.fmt.bufPrint(buf, "bkpt{} #{}", .{ condName(cond), value }) catch error.NoSpaceLeft;
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

    if (arm_exec.isArmDivide(word)) {
        return formatArmDivide(buf, word, cond);
    }

    if (arm_exec.isBitReverse(word)) {
        return formatArmUnaryReg(buf, "rbit", word, cond);
    }

    if (arm_exec.isBitfieldClear(word)) {
        const msb = @intCast(u5, (word >> 16) & 0x1f);
        const lsb = @intCast(u5, (word >> 7) & 0x1f);
        const width = if (msb >= lsb) @as(u32, msb) - @as(u32, lsb) + 1 else @as(u32, 0);
        const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
        return std.fmt.bufPrint(buf, "bfc{} {}, #{}, #{}", .{
            condName(cond),
            arm_state.regName(dest),
            lsb,
            width,
        }) catch error.NoSpaceLeft;
    }

    if (arm_exec.isBitfieldInsert(word)) {
        const msb = @intCast(u5, (word >> 16) & 0x1f);
        const lsb = @intCast(u5, (word >> 7) & 0x1f);
        const width = if (msb >= lsb) @as(u32, msb) - @as(u32, lsb) + 1 else @as(u32, 0);
        const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
        const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
        return std.fmt.bufPrint(buf, "bfi{} {}, {}, #{}, #{}", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(source),
            lsb,
            width,
        }) catch error.NoSpaceLeft;
    }

    if (arm_exec.isUnsignedBitfieldExtract(word) or arm_exec.isSignedBitfieldExtract(word)) {
        const name = if (arm_exec.isSignedBitfieldExtract(word)) "sbfx" else "ubfx";
        const width = ((word >> 16) & 0x1f) + 1;
        const lsb = (word >> 7) & 0x1f;
        const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
        const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
        return std.fmt.bufPrint(buf, "{}{} {}, {}, #{}, #{}", .{
            name,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(source),
            lsb,
            width,
        }) catch error.NoSpaceLeft;
    }

    if (arm_exec.isMoveTop(word)) {
        const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
        const imm16 = (((word >> 16) & 0xf) << 12) | (word & 0xfff);
        return std.fmt.bufPrint(buf, "movt{} {}, #{}", .{
            condName(cond),
            arm_state.regName(dest),
            imm16,
        }) catch error.NoSpaceLeft;
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

    if (saturatingBinaryName(word)) |op| {
        return formatSaturatingBinary(buf, op, word, cond);
    }

    if (isSaturatingArmFormat(word)) {
        return formatSaturatingArm(buf, word, cond);
    }

    if (parallelSaturatingName(word)) |op| {
        return formatParallelThreeReg(buf, op, word, cond);
    }

    if (parallelWrappingName(word)) |op| {
        return formatParallelThreeReg(buf, op, word, cond);
    }

    if (parallelHalvingName(word)) |op| {
        return formatParallelThreeReg(buf, op, word, cond);
    }

    if (isByteSelectFormat(word)) {
        return formatByteSelect(buf, word, cond);
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
