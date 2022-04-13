const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const Core64 = main.Core64;
const Core64Error = main.Core64Error;
const FaultKind64 = main.FaultKind64;
const CacheAction64 = main.CacheAction64;
const FloatNanMode64 = main.FloatNanMode64;
const HostHooks64 = main.HostHooks64;
usingnamespace @import("a64_math_flags.zig");
usingnamespace @import("a64_logic_masks.zig");
usingnamespace @import("a64_immediate_vectors.zig");
usingnamespace @import("a64_divide_crc.zig");
usingnamespace @import("a64_crypto_tables.zig");
usingnamespace @import("a64_float_control.zig");
usingnamespace @import("a64_float_arithmetic.zig");
usingnamespace @import("a64_float_minmax.zig");
usingnamespace @import("a64_float_nan.zig");
usingnamespace @import("a64_vector_access.zig");
usingnamespace @import("a64_crypto_vectors.zig");
usingnamespace @import("a64_vector_integer.zig");
usingnamespace @import("a64_vector_float.zig");
usingnamespace @import("a64_vector_compare.zig");
usingnamespace @import("a64_vector_shift.zig");
usingnamespace @import("a64_count_bits.zig");
usingnamespace @import("a64_memory_bits.zig");

pub const Core64Methods = struct {
    pub fn runOne(self: *Core64) Core64Error!void {
        if (self.hooks.memory.readCode) |read_code| {
            const word = read_code(self.state.pc, self.hooks.context);
            if (self.runPcRelative(word)) {
                return;
            }
            if (self.runBranch(word)) {
                return;
            }
            if (self.runCompareBranch(word)) {
                return;
            }
            if (self.runSupervisorCall(word)) {
                return;
            }
            const load_store = self.runLoadStore(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (load_store) {
                return;
            }
            const pair_load_store = self.runPairLoadStore(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (pair_load_store) {
                return;
            }
            const vector_pair_load_store = self.runVectorPairLoadStore(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_pair_load_store) {
                return;
            }
            const vector_structure_transfer = self.runVectorStructureTransfer(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_structure_transfer) {
                return;
            }
            const logical_immediate = self.runLogicalImmediate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (logical_immediate) {
                return;
            }
            const logical_shifted = self.runLogicalShifted(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (logical_shifted) {
                return;
            }
            const add_sub_immediate = self.runAddSubImmediate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (add_sub_immediate) {
                return;
            }
            const add_shifted = self.runAddShifted(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (add_shifted) {
                return;
            }
            const add_sub_extended = self.runAddSubExtended(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (add_sub_extended) {
                return;
            }
            const add_sub_carry = self.runAddSubCarry(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (add_sub_carry) {
                return;
            }
            const wide_move = self.runWideMove(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (wide_move) {
                return;
            }
            const bitfield_move = self.runBitfieldMove(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (bitfield_move) {
                return;
            }
            const extract_register = self.runExtractRegister(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (extract_register) {
                return;
            }
            if (self.runConditionalSelect(word)) {
                return;
            }
            if (self.runConditionalCompare(word)) {
                return;
            }
            const byte_reverse = self.runByteReverse(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (byte_reverse) {
                return;
            }
            const float_immediate = self.runFloatImmediate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (float_immediate) {
                return;
            }
            const float_unary = self.runFloatUnary(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (float_unary) {
                return;
            }
            const float_convert = self.runFloatConvert(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (float_convert) {
                return;
            }
            const integer_to_float = self.runIntegerToFloat(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (integer_to_float) {
                return;
            }
            const float_general_move = self.runFloatGeneralMove(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (float_general_move) {
                return;
            }
            const fixed_to_integer = self.runFixedToInteger(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (fixed_to_integer) {
                return;
            }
            const float_to_integer = self.runFloatToInteger(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (float_to_integer) {
                return;
            }
            const float_binary = self.runFloatBinary(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (float_binary) {
                return;
            }
            const float_compare = self.runFloatCompare(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (float_compare) {
                return;
            }
            const float_conditional_compare = self.runFloatConditionalCompare(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (float_conditional_compare) {
                return;
            }
            const float_select = self.runFloatSelect(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (float_select) {
                return;
            }
            if (self.runAesRound(word)) {
                return;
            }
            if (self.runHashRotate(word)) {
                return;
            }
            const vector_duplicate = self.runVectorDuplicate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_duplicate) {
                return;
            }
            const scalar_duplicate = self.runScalarDuplicate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (scalar_duplicate) {
                return;
            }
            const scalar_integer_float = self.runScalarIntegerToFloat(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (scalar_integer_float) {
                return;
            }
            const vector_extract = self.runVectorExtractToRegister(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_extract) {
                return;
            }
            const register_insert = self.runRegisterInsertElement(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (register_insert) {
                return;
            }
            const vector_insert = self.runVectorInsertElement(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_insert) {
                return;
            }
            const vector_immediate = self.runVectorModifiedImmediate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_immediate) {
                return;
            }
            const vector_interleave = self.runVectorInterleave(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_interleave) {
                return;
            }
            const vector_narrow = self.runVectorNarrow(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_narrow) {
                return;
            }
            const vector_count = self.runVectorCount(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_count) {
                return;
            }
            if (self.runVectorReverseBits(word)) {
                return;
            }
            const vector_reverse_half = self.runVectorReverseHalfBytes(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_reverse_half) {
                return;
            }
            const vector_reverse_word = self.runVectorReverseWordBytes(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_reverse_word) {
                return;
            }
            const vector_reverse_doubleword = self.runVectorReverseDoublewordBytes(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_reverse_doubleword) {
                return;
            }
            const vector_compare_zero = self.runVectorCompareZero(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_compare_zero) {
                return;
            }
            const scalar_vector_compare_zero = self.runScalarVectorCompareZero(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (scalar_vector_compare_zero) {
                return;
            }
            const vector_absolute = self.runVectorAbsolute(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_absolute) {
                return;
            }
            const scalar_vector_absolute = self.runScalarVectorAbsolute(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (scalar_vector_absolute) {
                return;
            }
            const vector_negate = self.runVectorNegate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_negate) {
                return;
            }
            const scalar_vector_negate = self.runScalarVectorNegate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (scalar_vector_negate) {
                return;
            }
            const vector_float = self.runVectorFloatBinary(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_float) {
                return;
            }
            const vector_signed_integer_float = self.runVectorSignedIntegerToFloat(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_signed_integer_float) {
                return;
            }
            const vector_shift_immediate = self.runVectorShiftImmediate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_shift_immediate) {
                return;
            }
            const scalar_shift_immediate = self.runScalarShiftImmediate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (scalar_shift_immediate) {
                return;
            }
            const scalar_vector_arithmetic = self.runScalarVectorArithmetic(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (scalar_vector_arithmetic) {
                return;
            }
            const scalar_pair_add = self.runScalarPairAdd(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (scalar_pair_add) {
                return;
            }
            const vector_add = self.runVectorAdd(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_add) {
                return;
            }
            const vector_multiply_add_element = self.runVectorMultiplyAddByElement(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_multiply_add_element) {
                return;
            }
            const vector_widening_arithmetic = self.runVectorWideningArithmetic(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_widening_arithmetic) {
                return;
            }
            const vector_pair_add = self.runVectorPairAdd(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_pair_add) {
                return;
            }
            const vector_equal = self.runVectorEqual(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_equal) {
                return;
            }
            const vector_greater = self.runVectorGreaterSigned(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_greater) {
                return;
            }
            const vector_higher = self.runVectorGreaterUnsigned(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_higher) {
                return;
            }
            const vector_unsigned_shift = self.runVectorUnsignedShift(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_unsigned_shift) {
                return;
            }
            const vector_min_max = self.runVectorMinMax(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_min_max) {
                return;
            }
            const vector_difference = self.runVectorUnsignedDifference(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_difference) {
                return;
            }
            if (self.runVectorNot(word)) {
                return;
            }
            if (self.runVectorAnd(word)) {
                return;
            }
            if (self.runVectorThreeInputBitwise(word)) {
                return;
            }
            if (self.runVectorThreeInputHash(word)) {
                return;
            }
            if (self.runVectorRotatedXor(word)) {
                return;
            }
            if (self.runVectorWideSchedule(word)) {
                return;
            }
            if (self.runVectorMessageSchedule(word)) {
                return;
            }
            if (self.runVectorShaSchedule(word)) {
                return;
            }
            if (self.runDivide(word)) {
                return;
            }
            const crc = self.runCrc(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (crc) {
                return;
            }
            if (self.runVariableShift(word)) {
                return;
            }
            const cache_maintenance = self.runCacheMaintenance(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (cache_maintenance) {
                return;
            }
            if (self.runClearExclusive(word)) {
                return;
            }
            if (self.runBarrier(word)) {
                return;
            }
            if (self.runSystemRegisterWrite(word)) {
                return;
            }
            if (self.runSystemRegisterRead(word)) {
                return;
            }
            if (self.runSystemHint(word)) {
                return;
            }
            if (self.runLeadingZeroCount(word)) {
                return;
            }
            if (self.runMultiplyAdd(word)) {
                return;
            }
            if (self.runMultiplyHigh(word)) {
                return;
            }
            if (self.runLongMultiplyAdd(word)) {
                return;
            }
        }
        const callback = self.hooks.fallback orelse return error.MissingFallback;
        callback(self.state.pc, 1, &self.state, self.hooks.context);
    }

    pub fn raiseFault(self: *Core64, err: Core64Error) Core64Error!void {
        const kind = switch (err) {
            error.UnallocatedEncoding => FaultKind64.unallocated_encoding,
            error.ReservedInstruction => FaultKind64.reserved_value,
            error.Unpredictable => FaultKind64.unpredictable_instruction,
            else => return err,
        };
        self.state.pc +%= 4;
        const callback = self.hooks.exception orelse return err;
        callback(self.state.pc, kind, self.hooks.context);
    }
};
