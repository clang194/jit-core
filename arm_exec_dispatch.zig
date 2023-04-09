const arm_state = @import("arm_state.zig");
const bits = @import("bits.zig");
usingnamespace @import("arm_exec_types.zig");
usingnamespace @import("arm_exec_fetch_decode.zig");
usingnamespace @import("arm_exec_coprocessor.zig");
usingnamespace @import("arm_exec_float_decode.zig");
usingnamespace @import("arm_exec_float_run.zig");
usingnamespace @import("arm_exec_multiply_run.zig");
usingnamespace @import("arm_exec_float_math.zig");
usingnamespace @import("arm_exec_system_run.zig");
usingnamespace @import("arm_exec_divide_run.zig");
usingnamespace @import("arm_exec_crc_run.zig");
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

fn usesRetiredArmCondition(word: u32) bool {
    if ((word >> 28) != 0xf) {
        return false;
    }

    const folded = word & 0x0fffffff;
    return usesExternalArmHandler(folded) or
        isFloatAdd(folded) or
        isFloatMulAdd(folded) or
        isFloatMulSub(folded) or
        isFloatNegMulAdd(folded) or
        isFloatNegMulSub(folded) or
        isFloatSub(folded) or
        isFloatMul(folded) or
        isFloatNegMul(folded) or
        isFloatDiv(folded) or
        isFloatMoveCoreToPairLow(folded) or
        isFloatMovePairLowToCore(folded) or
        isFloatMoveCoreToWord(folded) or
        isFloatMoveWordToCore(folded) or
        isFloatMoveTwoCoreToTwoWord(folded) or
        isFloatMoveTwoWordToTwoCore(folded) or
        isFloatMoveTwoCoreToPair(folded) or
        isFloatMovePairToTwoCore(folded) or
        isFloatMoveReg(folded) or
        isFloatLoad(folded) or
        isFloatStore(folded) or
        isFloatPush(folded) or
        isFloatStoreMultiple(folded) or
        isFloatPop(folded) or
        isFloatLoadMultiple(folded) or
        isFloatAbs(folded) or
        isFloatNeg(folded) or
        isFloatSqrt(folded) or
        isFloatConvertWidth(folded) or
        isFloatConvertIntToFloat(folded) or
        isFloatConvertToUnsigned(folded) or
        isFloatConvertToSigned(folded) or
        isFloatCompare(folded) or
        isFloatStatusWrite(folded) or
        isFloatStatusRead(folded) or
        isSignedTopMultiply(folded) or
        halfMultiplyOp(folded) != null or
        dualMultiplyOp(folded) != null or
        isLoadExclusive(folded) or
        isStoreExclusive(folded) or
        isSwap(folded) or
        isStatusRead(folded) or
        isStatusWriteImmediate(folded) or
        isStatusWriteRegister(folded) or
        isCountLeadingZeros(folded) or
        isArmDivide(folded) or
        isArmCrc(folded) or
        isBitReverse(folded) or
        isBitfieldClear(folded) or
        isBitfieldInsert(folded) or
        isUnsignedBitfieldExtract(folded) or
        isSignedBitfieldExtract(folded) or
        isMoveTop(folded) or
        isMoveLow(folded) or
        isSignedSaturatingWord(folded) or
        isScalarSaturatingMove(folded) or
        isHalfSaturatingMove(folded) or
        isUnsignedSaturatingSubBytes(folded) or
        isSignedSaturatingSubBytes(folded) or
        isUnsignedSaturatingAddBytes(folded) or
        isSignedSaturatingAddBytes(folded) or
        isUnsignedSaturatingSubHalves(folded) or
        isSignedSaturatingSubHalves(folded) or
        isUnsignedSaturatingAddHalves(folded) or
        isSignedSaturatingAddHalves(folded) or
        isUnsignedSaturatingAddSubHalves(folded) or
        isUnsignedSaturatingSubAddHalves(folded) or
        isSignedSaturatingAddSubHalves(folded) or
        isSignedSaturatingSubAddHalves(folded) or
        isUnsignedHalvingAddBytes(folded) or
        isUnsignedHalvingAddHalves(folded) or
        isSignedHalvingAddBytes(folded) or
        isSignedHalvingAddHalves(folded) or
        isUnsignedHalvingAddSubHalves(folded) or
        isUnsignedHalvingSubAddHalves(folded) or
        isSignedHalvingAddSubHalves(folded) or
        isSignedHalvingSubAddHalves(folded) or
        isUnsignedWrappingAddSubHalves(folded) or
        isUnsignedWrappingSubAddHalves(folded) or
        isSignedWrappingAddSubHalves(folded) or
        isSignedWrappingSubAddHalves(folded) or
        isUnsignedHalvingSubBytes(folded) or
        isSignedHalvingSubBytes(folded) or
        isUnsignedHalvingSubHalves(folded) or
        isSignedHalvingSubHalves(folded) or
        isUnsignedWrappingAddBytes(folded) or
        isSignedWrappingAddBytes(folded) or
        isUnsignedWrappingAddHalves(folded) or
        isSignedWrappingAddHalves(folded) or
        isUnsignedWrappingSubBytes(folded) or
        isSignedWrappingSubBytes(folded) or
        isUnsignedWrappingSubHalves(folded) or
        isSignedWrappingSubHalves(folded) or
        isByteSelect(folded) or
        isUnsignedAbsDiffSum(folded) or
        isHalfwordPack(folded) or
        isLoadMultiple(folded) or
        isStoreMultiple(folded) or
        isBranchImmediate(folded) or
        isBranchExchange(folded) or
        isDataProcessing(folded) or
        isMultiply(folded) or
        isLoadWord(folded) or
        isLoadByte(folded) or
        isLoadHalf(folded) or
        isLoadSignedByte(folded) or
        isLoadSignedHalf(folded) or
        isLoadDouble(folded) or
        isStoreWord(folded) or
        isStoreByte(folded) or
        isStoreHalf(folded) or
        isStoreDouble(folded) or
        isAdcImmediate(folded) or
        isCmpImmediate(folded) or
        isRev(folded) or
        isRevHalfwords(folded) or
        isRevSignedHalf(folded) or
        extendOp(folded) != null or
        isSupervisorCall(folded) or
        isBreakpoint(folded);
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

    if (isFloatCompare(word)) {
        return runFloatCompare(word, state, hooks, pc);
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
        return runArmHint(word, state, hooks, pc);
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

    if (isArmBarrier(word)) {
        return runArmBarrier(word, state, hooks, pc);
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

    if (isCountLeadingZeros(word)) {
        return runCountLeadingZeros(word, state, pc);
    }

    if (isArmDivide(word)) {
        return runArmDivide(word, state, pc);
    }

    if (isArmCrc(word)) {
        return runArmCrc(word, state, pc);
    }

    if (isBitReverse(word)) {
        return runBitReverse(word, state, pc);
    }

    if (isBitfieldClear(word)) {
        return runBitfieldClear(word, state, pc);
    }

    if (isBitfieldInsert(word)) {
        return runBitfieldInsert(word, state, pc);
    }

    if (isUnsignedBitfieldExtract(word)) {
        return runBitfieldExtract(word, state, pc, false);
    }

    if (isSignedBitfieldExtract(word)) {
        return runBitfieldExtract(word, state, pc, true);
    }

    if (isMoveTop(word)) {
        return runMoveTop(word, state, pc);
    }

    if (isMoveLow(word)) {
        return runMoveLow(word, state, pc);
    }

    if (isSignedSaturatingWord(word)) {
        return runSignedSaturatingWord(word, state, pc);
    }

    if (isScalarSaturatingMove(word)) {
        return runScalarSaturatingMove(word, state, pc);
    }

    if (isHalfSaturatingMove(word)) {
        return runHalfSaturatingMove(word, state, pc);
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

    if (isUnsignedSaturatingAddSubHalves(word)) {
        return runUnsignedSaturatingMixedHalves(word, state, pc, true);
    }

    if (isUnsignedSaturatingSubAddHalves(word)) {
        return runUnsignedSaturatingMixedHalves(word, state, pc, false);
    }

    if (isSignedSaturatingAddSubHalves(word)) {
        return runSignedSaturatingMixedHalves(word, state, pc, true);
    }

    if (isSignedSaturatingSubAddHalves(word)) {
        return runSignedSaturatingMixedHalves(word, state, pc, false);
    }

    if (isUnsignedHalvingAddBytes(word)) {
        return runUnsignedHalvingAddBytes(word, state, pc);
    }

    if (isUnsignedHalvingAddHalves(word)) {
        return runUnsignedHalvingAddHalves(word, state, pc);
    }

    if (isSignedHalvingAddBytes(word)) {
        return runSignedHalvingAddBytes(word, state, pc);
    }

    if (isSignedHalvingAddHalves(word)) {
        return runSignedHalvingAddHalves(word, state, pc);
    }

    if (isUnsignedHalvingAddSubHalves(word)) {
        return runUnsignedHalvingMixedHalves(word, state, pc, true);
    }

    if (isUnsignedHalvingSubAddHalves(word)) {
        return runUnsignedHalvingMixedHalves(word, state, pc, false);
    }

    if (isSignedHalvingAddSubHalves(word)) {
        return runSignedHalvingMixedHalves(word, state, pc, true);
    }

    if (isSignedHalvingSubAddHalves(word)) {
        return runSignedHalvingMixedHalves(word, state, pc, false);
    }

    if (isUnsignedWrappingAddSubHalves(word)) {
        return runUnsignedWrappingMixedHalves(word, state, pc, true);
    }

    if (isUnsignedWrappingSubAddHalves(word)) {
        return runUnsignedWrappingMixedHalves(word, state, pc, false);
    }

    if (isSignedWrappingAddSubHalves(word)) {
        return runSignedWrappingMixedHalves(word, state, pc, true);
    }

    if (isSignedWrappingSubAddHalves(word)) {
        return runSignedWrappingMixedHalves(word, state, pc, false);
    }

    if (isUnsignedHalvingSubBytes(word)) {
        return runUnsignedHalvingSubBytes(word, state, pc);
    }

    if (isSignedHalvingSubBytes(word)) {
        return runSignedHalvingSubBytes(word, state, pc);
    }

    if (isUnsignedHalvingSubHalves(word)) {
        return runUnsignedHalvingSubHalves(word, state, pc);
    }

    if (isSignedHalvingSubHalves(word)) {
        return runSignedHalvingSubHalves(word, state, pc);
    }

    if (isUnsignedWrappingAddBytes(word)) {
        return runUnsignedWrappingAddBytes(word, state, pc);
    }

    if (isSignedWrappingAddBytes(word)) {
        return runSignedWrappingAddBytes(word, state, pc);
    }

    if (isUnsignedWrappingAddHalves(word)) {
        return runUnsignedWrappingAddHalves(word, state, pc);
    }

    if (isSignedWrappingAddHalves(word)) {
        return runSignedWrappingAddHalves(word, state, pc);
    }

    if (isUnsignedWrappingSubBytes(word)) {
        return runUnsignedWrappingSubBytes(word, state, pc);
    }

    if (isSignedWrappingSubBytes(word)) {
        return runSignedWrappingSubBytes(word, state, pc);
    }

    if (isUnsignedWrappingSubHalves(word)) {
        return runUnsignedWrappingSubHalves(word, state, pc);
    }

    if (isSignedWrappingSubHalves(word)) {
        return runSignedWrappingSubHalves(word, state, pc);
    }

    if (isByteSelect(word)) {
        return runByteSelect(word, state, pc);
    }

    if (isUnsignedAbsDiffSum(word)) {
        return runUnsignedAbsDiffSum(word, state, pc);
    }

    if (isHalfwordPack(word)) {
        return runHalfwordPack(word, state, pc);
    }

    if (isLoadMultiple(word)) {
        return runLoadMultiple(word, state, hooks, pc);
    }

    if (isStoreMultiple(word)) {
        return runStoreMultiple(word, state, hooks, pc);
    }

    if (coprocessorOp(word)) |_| {
        return runCoprocessor(word, state, hooks, pc);
    }

    if (usesRetiredArmCondition(word)) {
        return error.Unpredictable;
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

    if (isUndefinedInstruction(word)) {
        if (hooks.exception) |callback| {
            callback(pc, .undefined_instruction, state, hooks.context);
            return;
        }
        return error.UnknownInstruction;
    }

    if (isBreakpoint(word)) {
        const code = armCondition(word).?;
        if (code != .al and !hooks.resolve_unpredictable_cases) {
            return error.Unpredictable;
        }
        if (!state.conditionHolds(code)) {
            state.write(.pc, pc + 4);
            return;
        }
        if (hooks.exception) |callback| {
            callback(pc, .breakpoint, state, hooks.context);
            return;
        }
        return error.UnknownInstruction;
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
