const arm_state = @import("arm_state.zig");
const arm_coprocessor = @import("arm_exec_coprocessor.zig");
const armCondition = arm_coprocessor.armCondition;
const coprocessorOp = arm_coprocessor.coprocessorOp;
const runCoprocessor = arm_coprocessor.runCoprocessor;
const runExternalArmHandler = arm_coprocessor.runExternalArmHandler;
const usesExternalArmHandler = arm_coprocessor.usesExternalArmHandler;
const arm_types = @import("arm_exec_types.zig");
const ArmStepError = arm_types.ArmStepError;
const AddResult = arm_types.AddResult;
const CoprocessorOp = arm_types.CoprocessorOp;
const DataOp = arm_types.DataOp;
const DualMultiplyOp = arm_types.DualMultiplyOp;
const ExtendOp = arm_types.ExtendOp;
const FloatBinaryOp = arm_types.FloatBinaryOp;
const FloatUnaryOp = arm_types.FloatUnaryOp;
const FloatVectorPlan = arm_types.FloatVectorPlan;
const HalfMultiplyOp = arm_types.HalfMultiplyOp;
const MultiplyOp = arm_types.MultiplyOp;
const SaturatingWordResult = arm_types.SaturatingWordResult;
const ShiftMode = arm_types.ShiftMode;
const ShiftResult = arm_types.ShiftResult;
const bits = @import("bits.zig");
usingnamespace @import("arm_exec_types.zig");
usingnamespace @import("arm_exec_fetch_decode.zig");
const arm_fetch_decode = @import("arm_exec_fetch_decode.zig");
const isAdcImmediate = arm_fetch_decode.isAdcImmediate;
const isArmBarrier = arm_fetch_decode.isArmBarrier;
const isArmCrc = arm_fetch_decode.isArmCrc;
const isArmDivide = arm_fetch_decode.isArmDivide;
const isBitReverse = arm_fetch_decode.isBitReverse;
const isBitfieldClear = arm_fetch_decode.isBitfieldClear;
const isBitfieldInsert = arm_fetch_decode.isBitfieldInsert;
const isBranchExchange = arm_fetch_decode.isBranchExchange;
const isBranchExchangeRegister = arm_fetch_decode.isBranchExchangeRegister;
const isBranchImmediate = arm_fetch_decode.isBranchImmediate;
const isBranchLinkExchangeImmediate = arm_fetch_decode.isBranchLinkExchangeImmediate;
const isBreakpoint = arm_fetch_decode.isBreakpoint;
const isByteSelect = arm_fetch_decode.isByteSelect;
const isClearExclusive = arm_fetch_decode.isClearExclusive;
const isCmpImmediate = arm_fetch_decode.isCmpImmediate;
const isCountLeadingZeros = arm_fetch_decode.isCountLeadingZeros;
const isDataProcessing = arm_fetch_decode.isDataProcessing;
const isEndianSelect = arm_fetch_decode.isEndianSelect;
const isHalfSaturatingMove = arm_fetch_decode.isHalfSaturatingMove;
const isHalfwordPack = arm_fetch_decode.isHalfwordPack;
const isLoadByte = arm_fetch_decode.isLoadByte;
const isLoadDouble = arm_fetch_decode.isLoadDouble;
const isLoadExclusive = arm_fetch_decode.isLoadExclusive;
const isLoadHalf = arm_fetch_decode.isLoadHalf;
const isLoadMultiple = arm_fetch_decode.isLoadMultiple;
const isLoadSignedByte = arm_fetch_decode.isLoadSignedByte;
const isLoadSignedHalf = arm_fetch_decode.isLoadSignedHalf;
const isLoadWord = arm_fetch_decode.isLoadWord;
const isMoveLow = arm_fetch_decode.isMoveLow;
const isMoveTop = arm_fetch_decode.isMoveTop;
const isMultiply = arm_fetch_decode.isMultiply;
const isRev = arm_fetch_decode.isRev;
const isRevHalfwords = arm_fetch_decode.isRevHalfwords;
const isRevSignedHalf = arm_fetch_decode.isRevSignedHalf;
const isScalarSaturatingMove = arm_fetch_decode.isScalarSaturatingMove;
const isSignedBitfieldExtract = arm_fetch_decode.isSignedBitfieldExtract;
const isSignedHalvingAddBytes = arm_fetch_decode.isSignedHalvingAddBytes;
const isSignedHalvingAddHalves = arm_fetch_decode.isSignedHalvingAddHalves;
const isSignedHalvingAddSubHalves = arm_fetch_decode.isSignedHalvingAddSubHalves;
const isSignedHalvingSubAddHalves = arm_fetch_decode.isSignedHalvingSubAddHalves;
const isSignedHalvingSubBytes = arm_fetch_decode.isSignedHalvingSubBytes;
const isSignedHalvingSubHalves = arm_fetch_decode.isSignedHalvingSubHalves;
const isSignedSaturatingAddBytes = arm_fetch_decode.isSignedSaturatingAddBytes;
const isSignedSaturatingAddHalves = arm_fetch_decode.isSignedSaturatingAddHalves;
const isSignedSaturatingAddSubHalves = arm_fetch_decode.isSignedSaturatingAddSubHalves;
const isSignedSaturatingSubAddHalves = arm_fetch_decode.isSignedSaturatingSubAddHalves;
const isSignedSaturatingSubBytes = arm_fetch_decode.isSignedSaturatingSubBytes;
const isSignedSaturatingSubHalves = arm_fetch_decode.isSignedSaturatingSubHalves;
const isSignedSaturatingWord = arm_fetch_decode.isSignedSaturatingWord;
const isSignedWrappingAddBytes = arm_fetch_decode.isSignedWrappingAddBytes;
const isSignedWrappingAddHalves = arm_fetch_decode.isSignedWrappingAddHalves;
const isSignedWrappingAddSubHalves = arm_fetch_decode.isSignedWrappingAddSubHalves;
const isSignedWrappingSubAddHalves = arm_fetch_decode.isSignedWrappingSubAddHalves;
const isSignedWrappingSubBytes = arm_fetch_decode.isSignedWrappingSubBytes;
const isSignedWrappingSubHalves = arm_fetch_decode.isSignedWrappingSubHalves;
const isStatusRead = arm_fetch_decode.isStatusRead;
const isStatusWriteImmediate = arm_fetch_decode.isStatusWriteImmediate;
const isStatusWriteRegister = arm_fetch_decode.isStatusWriteRegister;
const isStoreByte = arm_fetch_decode.isStoreByte;
const isStoreDouble = arm_fetch_decode.isStoreDouble;
const isStoreExclusive = arm_fetch_decode.isStoreExclusive;
const isStoreHalf = arm_fetch_decode.isStoreHalf;
const isStoreMultiple = arm_fetch_decode.isStoreMultiple;
const isStoreWord = arm_fetch_decode.isStoreWord;
const isSupervisorCall = arm_fetch_decode.isSupervisorCall;
const isSwap = arm_fetch_decode.isSwap;
const isUndefinedInstruction = arm_fetch_decode.isUndefinedInstruction;
const isUnsignedAbsDiffSum = arm_fetch_decode.isUnsignedAbsDiffSum;
const isUnsignedBitfieldExtract = arm_fetch_decode.isUnsignedBitfieldExtract;
const isUnsignedHalvingAddBytes = arm_fetch_decode.isUnsignedHalvingAddBytes;
const isUnsignedHalvingAddHalves = arm_fetch_decode.isUnsignedHalvingAddHalves;
const isUnsignedHalvingAddSubHalves = arm_fetch_decode.isUnsignedHalvingAddSubHalves;
const isUnsignedHalvingSubAddHalves = arm_fetch_decode.isUnsignedHalvingSubAddHalves;
const isUnsignedHalvingSubBytes = arm_fetch_decode.isUnsignedHalvingSubBytes;
const isUnsignedHalvingSubHalves = arm_fetch_decode.isUnsignedHalvingSubHalves;
const isUnsignedSaturatingAddBytes = arm_fetch_decode.isUnsignedSaturatingAddBytes;
const isUnsignedSaturatingAddHalves = arm_fetch_decode.isUnsignedSaturatingAddHalves;
const isUnsignedSaturatingAddSubHalves = arm_fetch_decode.isUnsignedSaturatingAddSubHalves;
const isUnsignedSaturatingSubAddHalves = arm_fetch_decode.isUnsignedSaturatingSubAddHalves;
const isUnsignedSaturatingSubBytes = arm_fetch_decode.isUnsignedSaturatingSubBytes;
const isUnsignedSaturatingSubHalves = arm_fetch_decode.isUnsignedSaturatingSubHalves;
const isUnsignedWrappingAddBytes = arm_fetch_decode.isUnsignedWrappingAddBytes;
const isUnsignedWrappingAddHalves = arm_fetch_decode.isUnsignedWrappingAddHalves;
const isUnsignedWrappingAddSubHalves = arm_fetch_decode.isUnsignedWrappingAddSubHalves;
const isUnsignedWrappingSubAddHalves = arm_fetch_decode.isUnsignedWrappingSubAddHalves;
const isUnsignedWrappingSubBytes = arm_fetch_decode.isUnsignedWrappingSubBytes;
const isUnsignedWrappingSubHalves = arm_fetch_decode.isUnsignedWrappingSubHalves;
const readArmWord = arm_fetch_decode.readArmWord;
const supervisorImmediate = arm_fetch_decode.supervisorImmediate;
usingnamespace @import("arm_exec_coprocessor.zig");
usingnamespace @import("arm_exec_float_decode.zig");
const arm_float_decode = @import("arm_exec_float_decode.zig");
const isArmNoOp = arm_float_decode.isArmNoOp;
const isFloatAbs = arm_float_decode.isFloatAbs;
const isFloatAdd = arm_float_decode.isFloatAdd;
const isFloatCompare = arm_float_decode.isFloatCompare;
const isFloatConvertIntToFloat = arm_float_decode.isFloatConvertIntToFloat;
const isFloatConvertToSigned = arm_float_decode.isFloatConvertToSigned;
const isFloatConvertToUnsigned = arm_float_decode.isFloatConvertToUnsigned;
const isFloatConvertWidth = arm_float_decode.isFloatConvertWidth;
const isFloatDiv = arm_float_decode.isFloatDiv;
const isFloatLoad = arm_float_decode.isFloatLoad;
const isFloatLoadMultiple = arm_float_decode.isFloatLoadMultiple;
const isFloatMoveCoreToPairLow = arm_float_decode.isFloatMoveCoreToPairLow;
const isFloatMoveCoreToWord = arm_float_decode.isFloatMoveCoreToWord;
const isFloatMovePairLowToCore = arm_float_decode.isFloatMovePairLowToCore;
const isFloatMovePairToTwoCore = arm_float_decode.isFloatMovePairToTwoCore;
const isFloatMoveReg = arm_float_decode.isFloatMoveReg;
const isFloatMoveTwoCoreToPair = arm_float_decode.isFloatMoveTwoCoreToPair;
const isFloatMoveTwoCoreToTwoWord = arm_float_decode.isFloatMoveTwoCoreToTwoWord;
const isFloatMoveTwoWordToTwoCore = arm_float_decode.isFloatMoveTwoWordToTwoCore;
const isFloatMoveWordToCore = arm_float_decode.isFloatMoveWordToCore;
const isFloatMul = arm_float_decode.isFloatMul;
const isFloatMulAdd = arm_float_decode.isFloatMulAdd;
const isFloatMulSub = arm_float_decode.isFloatMulSub;
const isFloatNeg = arm_float_decode.isFloatNeg;
const isFloatNegMul = arm_float_decode.isFloatNegMul;
const isFloatNegMulAdd = arm_float_decode.isFloatNegMulAdd;
const isFloatNegMulSub = arm_float_decode.isFloatNegMulSub;
const isFloatPop = arm_float_decode.isFloatPop;
const isFloatPush = arm_float_decode.isFloatPush;
const isFloatSqrt = arm_float_decode.isFloatSqrt;
const isFloatStatusRead = arm_float_decode.isFloatStatusRead;
const isFloatStatusWrite = arm_float_decode.isFloatStatusWrite;
const isFloatStore = arm_float_decode.isFloatStore;
const isFloatStoreMultiple = arm_float_decode.isFloatStoreMultiple;
const isFloatSub = arm_float_decode.isFloatSub;
const isHintNoOp = arm_float_decode.isHintNoOp;
usingnamespace @import("arm_exec_float_run.zig");
const arm_float_arith_run = @import("arm_exec_float_arith_run.zig");
const runFloatAdd = arm_float_arith_run.runFloatAdd;
const runFloatDiv = arm_float_arith_run.runFloatDiv;
const runFloatMul = arm_float_arith_run.runFloatMul;
const runFloatMulAcc = arm_float_arith_run.runFloatMulAcc;
const runFloatNegMul = arm_float_arith_run.runFloatNegMul;
const runFloatSub = arm_float_arith_run.runFloatSub;
const arm_float_convert_run = @import("arm_exec_float_convert_run.zig");
const runFloatAbs = arm_float_convert_run.runFloatAbs;
const runFloatCompare = arm_float_convert_run.runFloatCompare;
const runFloatConvertIntToFloat = arm_float_convert_run.runFloatConvertIntToFloat;
const runFloatConvertToSigned = arm_float_convert_run.runFloatConvertToSigned;
const runFloatConvertToUnsigned = arm_float_convert_run.runFloatConvertToUnsigned;
const runFloatConvertWidth = arm_float_convert_run.runFloatConvertWidth;
const runFloatNeg = arm_float_convert_run.runFloatNeg;
const runFloatSqrt = arm_float_convert_run.runFloatSqrt;
const runFloatStatusRead = arm_float_convert_run.runFloatStatusRead;
const runFloatStatusWrite = arm_float_convert_run.runFloatStatusWrite;
const arm_float_memory_run = @import("arm_exec_float_memory_run.zig");
const runFloatLoad = arm_float_memory_run.runFloatLoad;
const runFloatLoadMultiple = arm_float_memory_run.runFloatLoadMultiple;
const runFloatPop = arm_float_memory_run.runFloatPop;
const runFloatPush = arm_float_memory_run.runFloatPush;
const runFloatStore = arm_float_memory_run.runFloatStore;
const runFloatStoreMultiple = arm_float_memory_run.runFloatStoreMultiple;
const arm_float_move_run = @import("arm_exec_float_move_run.zig");
const runFloatMoveCoreToPairLow = arm_float_move_run.runFloatMoveCoreToPairLow;
const runFloatMoveCoreToWord = arm_float_move_run.runFloatMoveCoreToWord;
const runFloatMovePairLowToCore = arm_float_move_run.runFloatMovePairLowToCore;
const runFloatMovePairToTwoCore = arm_float_move_run.runFloatMovePairToTwoCore;
const runFloatMoveReg = arm_float_move_run.runFloatMoveReg;
const runFloatMoveTwoCoreToPair = arm_float_move_run.runFloatMoveTwoCoreToPair;
const runFloatMoveTwoCoreToTwoWord = arm_float_move_run.runFloatMoveTwoCoreToTwoWord;
const runFloatMoveTwoWordToTwoCore = arm_float_move_run.runFloatMoveTwoWordToTwoCore;
const runFloatMoveWordToCore = arm_float_move_run.runFloatMoveWordToCore;
usingnamespace @import("arm_exec_multiply_run.zig");
const arm_multiply_run = @import("arm_exec_multiply_run.zig");
const dualMultiplyOp = arm_multiply_run.dualMultiplyOp;
const halfMultiplyOp = arm_multiply_run.halfMultiplyOp;
const isSignedTopMultiply = arm_multiply_run.isSignedTopMultiply;
const runDualMultiply = arm_multiply_run.runDualMultiply;
const runHalfMultiply = arm_multiply_run.runHalfMultiply;
const runSignedTopMultiply = arm_multiply_run.runSignedTopMultiply;
usingnamespace @import("arm_exec_float_math.zig");
usingnamespace @import("arm_exec_system_run.zig");
const arm_system_run = @import("arm_exec_system_run.zig");
const runArmBarrier = arm_system_run.runArmBarrier;
const runArmHint = arm_system_run.runArmHint;
usingnamespace @import("arm_exec_divide_run.zig");
const arm_divide_run = @import("arm_exec_divide_run.zig");
const runArmDivide = arm_divide_run.runArmDivide;
usingnamespace @import("arm_exec_crc_run.zig");
const arm_crc_run = @import("arm_exec_crc_run.zig");
const runArmCrc = arm_crc_run.runArmCrc;
usingnamespace @import("arm_exec_status_branch.zig");
const arm_status_branch = @import("arm_exec_status_branch.zig");
const extendOp = arm_status_branch.extendOp;
const runBranchExchange = arm_status_branch.runBranchExchange;
const runBranchExchangeRegister = arm_status_branch.runBranchExchangeRegister;
const runBranchImmediate = arm_status_branch.runBranchImmediate;
const runBranchLinkExchangeImmediate = arm_status_branch.runBranchLinkExchangeImmediate;
const runCountLeadingZeros = arm_status_branch.runCountLeadingZeros;
const runStatusRead = arm_status_branch.runStatusRead;
const runStatusWriteImmediate = arm_status_branch.runStatusWriteImmediate;
const runStatusWriteRegister = arm_status_branch.runStatusWriteRegister;
usingnamespace @import("arm_exec_data_transfer.zig");
const arm_data_transfer = @import("arm_exec_data_transfer.zig");
const runDataProcessing = arm_data_transfer.runDataProcessing;
const runExtend = arm_data_transfer.runExtend;
const runLoadMultiple = arm_data_transfer.runLoadMultiple;
const runMultiply = arm_data_transfer.runMultiply;
const runStoreMultiple = arm_data_transfer.runStoreMultiple;
usingnamespace @import("arm_exec_saturate_scalar.zig");
const arm_saturate_scalar = @import("arm_exec_saturate_scalar.zig");
const runHalfSaturatingMove = arm_saturate_scalar.runHalfSaturatingMove;
const runScalarSaturatingMove = arm_saturate_scalar.runScalarSaturatingMove;
const runSignedSaturatingWord = arm_saturate_scalar.runSignedSaturatingWord;
usingnamespace @import("arm_exec_parallel_saturate.zig");
const arm_parallel_saturate = @import("arm_exec_parallel_saturate.zig");
const runSignedSaturatingAddBytes = arm_parallel_saturate.runSignedSaturatingAddBytes;
const runSignedSaturatingAddHalves = arm_parallel_saturate.runSignedSaturatingAddHalves;
const runSignedSaturatingMixedHalves = arm_parallel_saturate.runSignedSaturatingMixedHalves;
const runSignedSaturatingSubBytes = arm_parallel_saturate.runSignedSaturatingSubBytes;
const runSignedSaturatingSubHalves = arm_parallel_saturate.runSignedSaturatingSubHalves;
const runUnsignedSaturatingAddBytes = arm_parallel_saturate.runUnsignedSaturatingAddBytes;
const runUnsignedSaturatingAddHalves = arm_parallel_saturate.runUnsignedSaturatingAddHalves;
const runUnsignedSaturatingMixedHalves = arm_parallel_saturate.runUnsignedSaturatingMixedHalves;
const runUnsignedSaturatingSubBytes = arm_parallel_saturate.runUnsignedSaturatingSubBytes;
const runUnsignedSaturatingSubHalves = arm_parallel_saturate.runUnsignedSaturatingSubHalves;
usingnamespace @import("arm_exec_parallel_halve.zig");
const arm_parallel_halve = @import("arm_exec_parallel_halve.zig");
const runSignedHalvingAddBytes = arm_parallel_halve.runSignedHalvingAddBytes;
const runSignedHalvingAddHalves = arm_parallel_halve.runSignedHalvingAddHalves;
const runSignedHalvingMixedHalves = arm_parallel_halve.runSignedHalvingMixedHalves;
const runUnsignedHalvingAddBytes = arm_parallel_halve.runUnsignedHalvingAddBytes;
const runUnsignedHalvingAddHalves = arm_parallel_halve.runUnsignedHalvingAddHalves;
const runUnsignedHalvingMixedHalves = arm_parallel_halve.runUnsignedHalvingMixedHalves;
usingnamespace @import("arm_exec_parallel_wrap.zig");
const arm_parallel_add_wrap = @import("arm_exec_parallel_add_wrap.zig");
const runSignedWrappingAddBytes = arm_parallel_add_wrap.runSignedWrappingAddBytes;
const runSignedWrappingAddHalves = arm_parallel_add_wrap.runSignedWrappingAddHalves;
const runUnsignedWrappingAddBytes = arm_parallel_add_wrap.runUnsignedWrappingAddBytes;
const runUnsignedWrappingAddHalves = arm_parallel_add_wrap.runUnsignedWrappingAddHalves;
const arm_parallel_mixed_wrap = @import("arm_exec_parallel_mixed_wrap.zig");
const runSignedWrappingMixedHalves = arm_parallel_mixed_wrap.runSignedWrappingMixedHalves;
const runUnsignedWrappingMixedHalves = arm_parallel_mixed_wrap.runUnsignedWrappingMixedHalves;
const arm_parallel_sub_halve = @import("arm_exec_parallel_sub_halve.zig");
const runSignedHalvingSubBytes = arm_parallel_sub_halve.runSignedHalvingSubBytes;
const runSignedHalvingSubHalves = arm_parallel_sub_halve.runSignedHalvingSubHalves;
const runUnsignedHalvingSubBytes = arm_parallel_sub_halve.runUnsignedHalvingSubBytes;
const runUnsignedHalvingSubHalves = arm_parallel_sub_halve.runUnsignedHalvingSubHalves;
const arm_parallel_sub_wrap = @import("arm_exec_parallel_sub_wrap.zig");
const runSignedWrappingSubBytes = arm_parallel_sub_wrap.runSignedWrappingSubBytes;
const runSignedWrappingSubHalves = arm_parallel_sub_wrap.runSignedWrappingSubHalves;
const runUnsignedWrappingSubBytes = arm_parallel_sub_wrap.runUnsignedWrappingSubBytes;
const runUnsignedWrappingSubHalves = arm_parallel_sub_wrap.runUnsignedWrappingSubHalves;
usingnamespace @import("arm_exec_memory_run.zig");
const arm_memory_exclusive_run = @import("arm_exec_memory_exclusive_run.zig");
const runLoadExclusive = arm_memory_exclusive_run.runLoadExclusive;
const runStoreExclusive = arm_memory_exclusive_run.runStoreExclusive;
const runSwap = arm_memory_exclusive_run.runSwap;
const arm_memory_load_run = @import("arm_exec_memory_load_run.zig");
const runLoadByte = arm_memory_load_run.runLoadByte;
const runLoadDouble = arm_memory_load_run.runLoadDouble;
const runLoadHalf = arm_memory_load_run.runLoadHalf;
const runLoadSignedByte = arm_memory_load_run.runLoadSignedByte;
const runLoadSignedHalf = arm_memory_load_run.runLoadSignedHalf;
const runLoadWord = arm_memory_load_run.runLoadWord;
const arm_memory_store_run = @import("arm_exec_memory_store_run.zig");
const runStoreByte = arm_memory_store_run.runStoreByte;
const runStoreDouble = arm_memory_store_run.runStoreDouble;
const runStoreHalf = arm_memory_store_run.runStoreHalf;
const runStoreWord = arm_memory_store_run.runStoreWord;
usingnamespace @import("arm_exec_transfer_checks.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
usingnamespace @import("arm_exec_immediate_run.zig");
const arm_immediate_run = @import("arm_exec_immediate_run.zig");
const runAdcImmediate = arm_immediate_run.runAdcImmediate;
const runBitReverse = arm_immediate_run.runBitReverse;
const runBitfieldClear = arm_immediate_run.runBitfieldClear;
const runBitfieldExtract = arm_immediate_run.runBitfieldExtract;
const runBitfieldInsert = arm_immediate_run.runBitfieldInsert;
const runCmpImmediate = arm_immediate_run.runCmpImmediate;
const runMoveLow = arm_immediate_run.runMoveLow;
const runMoveTop = arm_immediate_run.runMoveTop;
const runRev = arm_immediate_run.runRev;
const runRevHalfwords = arm_immediate_run.runRevHalfwords;
const runRevSignedHalf = arm_immediate_run.runRevSignedHalf;
const arm_pack_select = @import("arm_exec_parallel_pack_select.zig");
const runByteSelect = arm_pack_select.runByteSelect;
const runHalfwordPack = arm_pack_select.runHalfwordPack;
const runUnsignedAbsDiffSum = arm_pack_select.runUnsignedAbsDiffSum;
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
        if (!hooks.keep_little_endian) {
            state.setBigEndian((word & 0x00000200) != 0);
        }
        state.write(.pc, pc + 4);
        return;
    }

    if (isStatusRead(word)) {
        return runStatusRead(word, state, pc);
    }

    if (isStatusWriteImmediate(word)) {
        return runStatusWriteImmediate(word, state, hooks, pc);
    }

    if (isStatusWriteRegister(word)) {
        return runStatusWriteRegister(word, state, hooks, pc);
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
