const std = @import("std");
const text_common = @import("arm_text_common_format.zig");
const condName = text_common.condName;
const text_types = @import("arm_text_types.zig");
const TextError = text_types.TextError;
const bits = @import("bits.zig");
const arm_exec = @import("arm_exec.zig");
const arm_state = @import("arm_state.zig");
const text_float_decode = @import("arm_text_float_decode.zig");
const formatArmExtend = text_float_decode.formatArmExtend;
const isFloatAbs = text_float_decode.isFloatAbs;
const isFloatAdd = text_float_decode.isFloatAdd;
const isFloatCompare = text_float_decode.isFloatCompare;
const isFloatConvertIntToFloat = text_float_decode.isFloatConvertIntToFloat;
const isFloatConvertToSigned = text_float_decode.isFloatConvertToSigned;
const isFloatConvertToUnsigned = text_float_decode.isFloatConvertToUnsigned;
const isFloatConvertWidth = text_float_decode.isFloatConvertWidth;
const isFloatDiv = text_float_decode.isFloatDiv;
const isFloatLoad = text_float_decode.isFloatLoad;
const isFloatLoadMultiple = text_float_decode.isFloatLoadMultiple;
const isFloatMoveCoreToPairLow = text_float_decode.isFloatMoveCoreToPairLow;
const isFloatMoveCoreToWord = text_float_decode.isFloatMoveCoreToWord;
const isFloatMovePairLowToCore = text_float_decode.isFloatMovePairLowToCore;
const isFloatMovePairToTwoCore = text_float_decode.isFloatMovePairToTwoCore;
const isFloatMoveReg = text_float_decode.isFloatMoveReg;
const isFloatMoveTwoCoreToPair = text_float_decode.isFloatMoveTwoCoreToPair;
const isFloatMoveTwoCoreToTwoWord = text_float_decode.isFloatMoveTwoCoreToTwoWord;
const isFloatMoveTwoWordToTwoCore = text_float_decode.isFloatMoveTwoWordToTwoCore;
const isFloatMoveWordToCore = text_float_decode.isFloatMoveWordToCore;
const isFloatMul = text_float_decode.isFloatMul;
const isFloatMulAdd = text_float_decode.isFloatMulAdd;
const isFloatMulSub = text_float_decode.isFloatMulSub;
const isFloatNeg = text_float_decode.isFloatNeg;
const isFloatNegMul = text_float_decode.isFloatNegMul;
const isFloatNegMulAdd = text_float_decode.isFloatNegMulAdd;
const isFloatNegMulSub = text_float_decode.isFloatNegMulSub;
const isFloatPop = text_float_decode.isFloatPop;
const isFloatPush = text_float_decode.isFloatPush;
const isFloatSqrt = text_float_decode.isFloatSqrt;
const isFloatStatusRead = text_float_decode.isFloatStatusRead;
const isFloatStatusWrite = text_float_decode.isFloatStatusWrite;
const isFloatStore = text_float_decode.isFloatStore;
const isFloatStoreMultiple = text_float_decode.isFloatStoreMultiple;
const isFloatSub = text_float_decode.isFloatSub;
const isStatusRead = text_float_decode.isStatusRead;
const isStatusWriteImmediate = text_float_decode.isStatusWriteImmediate;
const isStatusWriteRegister = text_float_decode.isStatusWriteRegister;
const isVfpCondition = text_float_decode.isVfpCondition;
const text_float_arith = @import("arm_text_float_arith_format.zig");
const formatFloatAdd = text_float_arith.formatFloatAdd;
const formatFloatDiv = text_float_arith.formatFloatDiv;
const formatFloatMoveCoreToPairLow = text_float_arith.formatFloatMoveCoreToPairLow;
const formatFloatMoveCoreToWord = text_float_arith.formatFloatMoveCoreToWord;
const formatFloatMovePairLowToCore = text_float_arith.formatFloatMovePairLowToCore;
const formatFloatMovePairToTwoCore = text_float_arith.formatFloatMovePairToTwoCore;
const formatFloatMoveReg = text_float_arith.formatFloatMoveReg;
const formatFloatMoveTwoCoreToPair = text_float_arith.formatFloatMoveTwoCoreToPair;
const formatFloatMoveTwoCoreToTwoWord = text_float_arith.formatFloatMoveTwoCoreToTwoWord;
const formatFloatMoveTwoWordToTwoCore = text_float_arith.formatFloatMoveTwoWordToTwoCore;
const formatFloatMoveWordToCore = text_float_arith.formatFloatMoveWordToCore;
const formatFloatMul = text_float_arith.formatFloatMul;
const formatFloatNegMul = text_float_arith.formatFloatNegMul;
const formatFloatSub = text_float_arith.formatFloatSub;
const formatFloatThree = text_float_arith.formatFloatThree;
const text_float_convert = @import("arm_text_float_convert_format.zig");
const formatFloatAbs = text_float_convert.formatFloatAbs;
const formatFloatCompare = text_float_convert.formatFloatCompare;
const formatFloatConvertIntToFloat = text_float_convert.formatFloatConvertIntToFloat;
const formatFloatConvertToInt = text_float_convert.formatFloatConvertToInt;
const formatFloatConvertWidth = text_float_convert.formatFloatConvertWidth;
const formatFloatNeg = text_float_convert.formatFloatNeg;
const formatFloatSqrt = text_float_convert.formatFloatSqrt;
const formatFloatStatusRead = text_float_convert.formatFloatStatusRead;
const formatFloatStatusWrite = text_float_convert.formatFloatStatusWrite;
const text_float_memory = @import("arm_text_float_memory_format.zig");
const formatFloatLoad = text_float_memory.formatFloatLoad;
const formatFloatLoadMultiple = text_float_memory.formatFloatLoadMultiple;
const formatFloatStack = text_float_memory.formatFloatStack;
const formatFloatStore = text_float_memory.formatFloatStore;
const formatFloatStoreMultiple = text_float_memory.formatFloatStoreMultiple;
const text_coprocessor = @import("arm_text_coprocessor_format.zig");
const formatCoprocessor = text_coprocessor.formatCoprocessor;
const text_block = @import("arm_text_block_format.zig");
const formatArmLoadMultiple = text_block.formatArmLoadMultiple;
const formatArmStoreMultiple = text_block.formatArmStoreMultiple;
const isArmLoadMultiple = text_block.isArmLoadMultiple;
const isArmStoreMultiple = text_block.isArmStoreMultiple;
const isSyncArmFormat = text_block.isSyncArmFormat;
const text_misc = @import("arm_text_misc_format.zig");
const formatMiscArm = text_misc.formatMiscArm;
const formatSyncArm = text_misc.formatSyncArm;
const isMiscArmFormat = text_misc.isMiscArmFormat;
const text_divide = @import("arm_text_divide_format.zig");
const formatArmDivide = text_divide.formatArmDivide;
const text_crc = @import("arm_text_crc_format.zig");
const formatArmCrc = text_crc.formatArmCrc;
const text_status = @import("arm_text_status_format.zig");
const formatStatusRead = text_status.formatStatusRead;
const formatStatusWriteImmediate = text_status.formatStatusWriteImmediate;
const formatStatusWriteRegister = text_status.formatStatusWriteRegister;
const text_system = @import("arm_text_system_format.zig");
const formatArmBarrier = text_system.formatArmBarrier;
const text_hint = @import("arm_text_hint_format.zig");
const formatArmPreload = text_hint.formatArmPreload;
const text_parallel = @import("arm_text_parallel_format.zig");
const armExtendText = text_parallel.armExtendText;
const formatByteSelect = text_parallel.formatByteSelect;
const formatDualMultiply = text_parallel.formatDualMultiply;
const formatExtendSource = text_parallel.formatExtendSource;
const formatHalfMultiply = text_parallel.formatHalfMultiply;
const formatPackHalfword = text_parallel.formatPackHalfword;
const formatParallelThreeReg = text_parallel.formatParallelThreeReg;
const formatSaturatingArm = text_parallel.formatSaturatingArm;
const formatSaturatingBinary = text_parallel.formatSaturatingBinary;
const formatSignedTopMultiply = text_parallel.formatSignedTopMultiply;
const isByteSelectFormat = text_parallel.isByteSelectFormat;
const isDualMultiplyFormat = text_parallel.isDualMultiplyFormat;
const isHalfMultiplyFormat = text_parallel.isHalfMultiplyFormat;
const isPackHalfword = text_parallel.isPackHalfword;
const isSaturatingArmFormat = text_parallel.isSaturatingArmFormat;
const isSignedTopMultiply = text_parallel.isSignedTopMultiply;
const parallelHalvingName = text_parallel.parallelHalvingName;
const parallelSaturatingName = text_parallel.parallelSaturatingName;
const parallelWrappingName = text_parallel.parallelWrappingName;
const saturatingBinaryName = text_parallel.saturatingBinaryName;
const text_multiply = @import("arm_text_multiply_format.zig");
const formatArmMultiply = text_multiply.formatArmMultiply;
const text_transfer = @import("arm_text_transfer_format.zig");
const formatArmTransferDouble = text_transfer.formatArmTransferDouble;
const formatArmTransferHalf = text_transfer.formatArmTransferHalf;
const formatArmTransferWord = text_transfer.formatArmTransferWord;
const text_data = @import("arm_text_data_format.zig");
const formatArmData = text_data.formatArmData;
const formatArmUnaryReg = text_data.formatArmUnaryReg;
const formatBranchExchangeImmediate = text_common.formatBranchExchangeImmediate;
const formatBranchImmediate = text_common.formatBranchImmediate;
const text_thumb32 = @import("arm_text_thumb32_format.zig");
const formatThumb32 = text_thumb32.formatThumb32;
usingnamespace @import("arm_text_types.zig");
usingnamespace @import("arm_text_float_format.zig");
usingnamespace @import("arm_text_coprocessor_format.zig");
usingnamespace @import("arm_text_block_format.zig");
usingnamespace @import("arm_text_misc_format.zig");
usingnamespace @import("arm_text_divide_format.zig");
usingnamespace @import("arm_text_crc_format.zig");
usingnamespace @import("arm_text_system_format.zig");
usingnamespace @import("arm_text_hint_format.zig");
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
        return formatArmPreload(buf, word);
    }

    if ((word & 0x0fffffff) == 0x0320f004) {
        return std.fmt.bufPrint(buf, "sev", .{}) catch error.NoSpaceLeft;
    }

    if ((word & 0x0fffffff) == 0x0320f005) {
        return std.fmt.bufPrint(buf, "sevl", .{}) catch error.NoSpaceLeft;
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

    if (arm_exec.isArmBarrier(word)) {
        return formatArmBarrier(buf, word);
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

    if (arm_exec.isArmCrc(word)) {
        return formatArmCrc(buf, word, arm_exec.isArmCrcAlt(word));
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

    if (arm_exec.isMoveLow(word)) {
        const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
        const imm16 = (((word >> 16) & 0xf) << 12) | (word & 0xfff);
        return std.fmt.bufPrint(buf, "movw{} {}, #{}", .{
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
