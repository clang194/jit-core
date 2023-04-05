const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const float_fixed = @import("float_fixed.zig");
const float_fused = @import("float_fused.zig");
const float_rounding = @import("float_rounding.zig");
const float_status = @import("float_status.zig");
const main = @import("a64_core.zig");
const Core64 = main.Core64;
const Core64Error = main.Core64Error;
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
usingnamespace @import("a64_vector_dot.zig");
usingnamespace @import("a64_count_bits.zig");
usingnamespace @import("a64_memory_bits.zig");

pub const Core64Methods = struct {
    pub fn runVectorFloatNegate(self: *Core64, word: u32) Core64Error!bool {
        const half = (word & 0xbffffc00) == 0x2ef8f800;
        const half_absolute = (word & 0xbffffc00) == 0x0ef8f800;
        const wide = (word & 0xbf3ffc00) == 0x2e20f800;
        const absolute = (word & 0xbfbffc00) == 0x0ea0f800;
        const equal_zero = (word & 0xbfbffc00) == 0x0ea0d800;
        const greater_zero = (word & 0xbfbffc00) == 0x0ea0c800;
        const greater_equal_zero = (word & 0xbfbffc00) == 0x2ea0c800;
        const less_zero = (word & 0xbfbffc00) == 0x0ea0e800;
        const less_equal_zero = (word & 0xbfbffc00) == 0x2ea0d800;
        const compare_zero = equal_zero or greater_zero or greater_equal_zero or less_zero or less_equal_zero;
        if (!half and !half_absolute and !wide and !absolute and !compare_zero) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = ((word >> 22) & 1) != 0;
        if ((wide or absolute or compare_zero) and double and !full) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = if (half) negateHalfFloatVector(full, source) else if (half_absolute) absoluteHalfFloatVector(full, source) else if (compare_zero) compareFloatZeroVector(self.state.floatControl(), double, full, source, if (equal_zero) .equal else if (greater_zero) .greater else if (greater_equal_zero) .greater_equal else if (less_zero) .less else .less_equal) else if (absolute) absoluteFloatVector(double, full, source) else negateFloatVector(double, full, source);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorFloatBinary(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbfa0fc00;
        if (masked != 0x0e20c400 and masked != 0x0e20d400 and masked != 0x0e20dc00 and masked != 0x0e20e400 and masked != 0x0e20f400 and masked != 0x0ea0c400 and masked != 0x0ea0d400 and masked != 0x0ea0f400 and masked != 0x2e20c400 and masked != 0x2e20d400 and masked != 0x2e20dc00 and masked != 0x2e20e400 and masked != 0x2e20ec00 and masked != 0x2e20f400 and masked != 0x2e20fc00 and masked != 0x2ea0c400 and masked != 0x2ea0d400 and masked != 0x2ea0e400 and masked != 0x2ea0ec00 and masked != 0x2ea0f400) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = ((word >> 22) & 1) != 0;
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const control = self.state.floatControl();
        const nan_mode = self.hooks.float_nan_mode;
        const result = if (masked == 0x0e20d400)
            addFloatVector(control, nan_mode, double, full, left, right)
        else if (masked == 0x2e20d400)
            addFloatPairsVector(control, nan_mode, double, full, left, right)
        else if (masked == 0x2e20c400)
            extremaFloatPairsVector(control, nan_mode, double, full, left, right, true, true)
        else if (masked == 0x2e20f400)
            extremaFloatPairsVector(control, nan_mode, double, full, left, right, true, false)
        else if (masked == 0x2ea0c400)
            extremaFloatPairsVector(control, nan_mode, double, full, left, right, false, true)
        else if (masked == 0x2ea0f400)
            extremaFloatPairsVector(control, nan_mode, double, full, left, right, false, false)
        else if (masked == 0x2e20dc00)
            multiplyFloatVector(control, nan_mode, double, full, left, right)
        else if (masked == 0x0e20dc00)
            multiplyExtendedFloatVector(control, nan_mode, double, full, left, right)
        else if (masked == 0x2e20fc00)
            divideFloatVector(control, nan_mode, double, full, left, right)
        else if (masked == 0x2ea0d400)
            absoluteDifferenceFloatVector(control, nan_mode, double, full, left, right)
        else if (masked == 0x0e20f400)
            maximumFloatVector(control, nan_mode, double, full, left, right)
        else if (masked == 0x0e20c400)
            maximumNumberFloatVector(control, nan_mode, double, full, left, right)
        else if (masked == 0x0ea0f400)
            minimumFloatVector(control, nan_mode, double, full, left, right)
        else if (masked == 0x0ea0c400)
            minimumNumberFloatVector(control, nan_mode, double, full, left, right)
        else if (masked == 0x0e20e400)
            equalFloatVector(control, double, full, left, right)
        else if (masked == 0x2e20e400)
            compareFloatVector(control, double, full, left, right, .greater_equal)
        else if (masked == 0x2e20ec00)
            compareFloatVector(control, double, full, absoluteFloatVector(double, full, left), absoluteFloatVector(double, full, right), .greater_equal)
        else if (masked == 0x2ea0e400)
            compareFloatVector(control, double, full, left, right, .greater)
        else if (masked == 0x2ea0ec00)
            compareFloatVector(control, double, full, absoluteFloatVector(double, full, left), absoluteFloatVector(double, full, right), .greater)
        else
            subtractFloatVector(control, nan_mode, double, full, left, right);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorFloatMulAdd(self: *Core64, word: u32) Core64Error!bool {
        const half_masked = word & 0xbfe0fc00;
        const half = half_masked == 0x0e400c00 or half_masked == 0x0ec00c00;
        const masked = word & 0xbfa0fc00;
        const subtracting = masked == 0x0ea0cc00;
        if (!half and masked != 0x0e20cc00 and !subtracting) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        if (half) {
            const addend = self.state.readVector(vectorRegFromWord(word));
            const left = self.state.readVector(vectorRegFromWord(word >> 5));
            const right = self.state.readVector(vectorRegFromWord(word >> 16));
            const adjusted_left = if (half_masked == 0x0ec00c00) negateHalfFloatVector(full, left) else left;
            const control = effectiveFloatControl(self.state.floatControl(), self.hooks.float_nan_mode);
            var status = float_status.FloatStatus.init(self.state.floatStatus());
            const result = fusedMultiplyAddHalfFloatVector(control, &status, full, addend, adjusted_left, right) catch return error.MissingFallback;
            self.state.writeFloatStatus(status.raw());
            self.state.writeVector(vectorRegFromWord(word), result);
            self.state.pc +%= 4;
            return true;
        }

        const double = ((word >> 22) & 1) != 0;
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const addend = self.state.readVector(vectorRegFromWord(word));
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const adjusted_left = if (subtracting) negateFloatVector(double, full, left) else left;
        const control = effectiveFloatControl(self.state.floatControl(), self.hooks.float_nan_mode);
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = fusedMultiplyAddFloatVector(control, &status, double, full, addend, adjusted_left, right) catch return error.MissingFallback;
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorFloatSquareRoot(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfbffc00) != 0x2ea1f800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = (word & 0x00400000) != 0;
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = squareRootFloatVector(self.state.floatControl(), self.hooks.float_nan_mode, double, full, source);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorRootStep(self: *Core64, word: u32) Core64Error!bool {
        const half = (word & 0xbfe0fc00) == 0x0ec03c00;
        if (!half and (word & 0xbfa0fc00) != 0x0ea0fc00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = ((word >> 22) & 1) != 0;
        if (!half and double and !full) {
            return error.ReservedInstruction;
        }

        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = if (half)
            rootStepHalfFloatVector(control, &status, full, left, right) catch return error.MissingFallback
        else
            rootStepFloatVector(control, &status, double, full, left, right) catch return error.MissingFallback;
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorReciprocalStep(self: *Core64, word: u32) Core64Error!bool {
        const half = (word & 0xbfe0fc00) == 0x0e403c00;
        if (!half and (word & 0xbfa0fc00) != 0x0e20fc00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = ((word >> 22) & 1) != 0;
        if (!half and double and !full) {
            return error.ReservedInstruction;
        }

        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = if (half)
            reciprocalStepHalfFloatVector(control, &status, full, left, right) catch return error.MissingFallback
        else
            reciprocalStepFloatVector(control, &status, double, full, left, right) catch return error.MissingFallback;
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorInverseRootEstimate(self: *Core64, word: u32) Core64Error!bool {
        const half = (word & 0xbffffc00) == 0x2ef9d800;
        if (!half and (word & 0xbfbffc00) != 0x2ea1d800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = (word & 0x00400000) != 0;
        if (!half and double and !full) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = inverseRootEstimateFloatVector(control, &status, half, double, full, source) catch return error.MissingFallback;
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorUnsignedInverseRootEstimate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfbffc00) != 0x2ea1c800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const wide = (word & 0x00400000) != 0;
        if (wide) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = inverseRootEstimateUnsignedVector(full, source);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorReciprocalEstimate(self: *Core64, word: u32) Core64Error!bool {
        const half = (word & 0xbffffc00) == 0x0ef9d800;
        if (!half and (word & 0xbfbffc00) != 0x2e21d800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = (word & 0x00400000) != 0;
        if (!half and double and !full) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = if (half)
            reciprocalEstimateHalfFloatVector(control, &status, full, source) catch return error.MissingFallback
        else
            reciprocalEstimateFloatVector(control, &status, double, full, source) catch return error.MissingFallback;
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorUnsignedReciprocalEstimate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfbffc00) != 0x2e21c800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const wide = (word & 0x00400000) != 0;
        if (wide) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = reciprocalEstimateUnsignedVector(full, source);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorSignedIntegerToFloat(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfbffc00) != 0x0e21d800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = ((word >> 22) & 1) != 0;
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = if (double)
            signedDoublewordsToFloatVector(source, 0)
        else
            signedWordsToFloatVector(full, source, 0);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorUnsignedIntegerToFloat(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfbffc00) != 0x2e21d800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = ((word >> 22) & 1) != 0;
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = if (double)
            unsignedDoublewordsToFloatVector(self.state.floatControl(), source, 0)
        else
            unsignedWordsToFloatVector(full, source, 0);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorFloatToInteger(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbfbffc00;
        const signed_nearest = masked == 0x0e21a800;
        const signed_negative = masked == 0x0e21b800;
        const signed_nearest_away = masked == 0x0e21c800;
        const signed_positive = masked == 0x0ea1a800;
        const signed_zero = masked == 0x0ea1b800;
        const unsigned_nearest = masked == 0x2e21a800;
        const unsigned_negative = masked == 0x2e21b800;
        const unsigned_nearest_away = masked == 0x2e21c800;
        const unsigned_positive = masked == 0x2ea1a800;
        const unsigned_zero = masked == 0x2ea1b800;
        if (!signed_nearest and !signed_negative and !signed_nearest_away and !signed_positive and !signed_zero and !unsigned_nearest and !unsigned_negative and !unsigned_nearest_away and !unsigned_positive and !unsigned_zero) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = ((word >> 22) & 1) != 0;
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const unsigned_result = unsigned_nearest or unsigned_negative or unsigned_nearest_away or unsigned_positive or unsigned_zero;
        const rounding = if (signed_nearest or unsigned_nearest)
            float_rounding.RoundingMode.nearest
        else if (signed_negative or unsigned_negative)
            float_rounding.RoundingMode.negative
        else if (signed_nearest_away or unsigned_nearest_away)
            float_rounding.RoundingMode.nearest_away
        else if (signed_positive or unsigned_positive)
            float_rounding.RoundingMode.positive
        else
            float_rounding.RoundingMode.zero;
        const result = fixedFloatVector(control, &status, double, full, 0, unsigned_result, rounding, source) catch return error.MissingFallback;
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorFloatRound(self: *Core64, word: u32) Core64Error!bool {
        const half_masked = word & 0xbffffc00;
        const half_nearest = half_masked == 0x0e798800;
        const half_negative = half_masked == 0x0e799800;
        const half_positive = half_masked == 0x0ef98800;
        const half_zero = half_masked == 0x0ef99800;
        const half_nearest_away = half_masked == 0x2e798800;
        const half_exact = half_masked == 0x2e799800;
        const half_current = half_masked == 0x2ef99800;
        const half = half_nearest or half_negative or half_positive or half_zero or half_nearest_away or half_exact or half_current;
        const masked = word & 0xbfbffc00;
        const nearest = masked == 0x0e218800;
        const negative = masked == 0x0e219800;
        const positive = masked == 0x0ea18800;
        const zero = masked == 0x0ea19800;
        const nearest_away = masked == 0x2e218800;
        const exact = masked == 0x2e219800;
        const current = masked == 0x2ea19800;
        if (!half and !nearest and !negative and !positive and !zero and !nearest_away and !exact and !current) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = ((word >> 22) & 1) != 0;
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const rounding = if (nearest or half_nearest)
            float_rounding.RoundingMode.nearest
        else if (negative or half_negative)
            float_rounding.RoundingMode.negative
        else if (positive or half_positive)
            float_rounding.RoundingMode.positive
        else if (zero or half_zero)
            float_rounding.RoundingMode.zero
        else if (nearest_away or half_nearest_away)
            float_rounding.RoundingMode.nearest_away
        else
            self.state.floatControl().rounding();
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = roundIntegralFloatVector(control, &status, half, double, full, rounding, exact or half_exact, source) catch return error.MissingFallback;
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorFloatWiden(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfbffc00) != 0x0e617800) {
            return false;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = widenFloatVector(control, &status, ((word >> 22) & 1) == 0, source, (word & 0x40000000) != 0) catch return error.MissingFallback;
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorFloatNarrow(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfbffc00) != 0x0e616800) {
            return false;
        }

        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const narrowed = narrowFloatVector(control, &status, ((word >> 22) & 1) == 0, self.state.readVector(vectorRegFromWord(word >> 5))) catch return error.MissingFallback;
        const result = if ((word & 0x40000000) != 0)
            a64_state.VectorValue{ .low = self.state.readVector(vectorRegFromWord(word)).low, .high = narrowed }
        else
            a64_state.VectorValue{ .low = narrowed, .high = 0 };
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorFloatNarrowOdd(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfbffc00) != 0x2e216800) {
            return false;
        }

        if ((word & 0x00800000) == 0) {
            return error.UnallocatedEncoding;
        }

        const narrowed = narrowDoubleFloatVectorOdd(self.state.floatControl(), self.state.readVector(vectorRegFromWord(word >> 5)));
        const result = if ((word & 0x40000000) != 0)
            a64_state.VectorValue{ .low = self.state.readVector(vectorRegFromWord(word)).low, .high = narrowed }
        else
            a64_state.VectorValue{ .low = narrowed, .high = 0 };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorFloatAcrossMinMax(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbfbffc00;
        const max_number = masked == 0x2e30c800;
        const max_plain = masked == 0x2e30f800;
        const min_number = masked == 0x2eb0c800;
        const min_plain = masked == 0x2eb0f800;
        if (!max_number and !max_plain and !min_number and !min_plain) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = (word & 0x00400000) != 0;
        if (!full or double) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const control = self.state.floatControl();
        const nan_mode = self.hooks.float_nan_mode;
        const left = if (max_number)
            floatMaxNumber(control, nan_mode, false, vectorElement(source, 0, 4), vectorElement(source, 1, 4))
        else if (max_plain)
            floatMax(control, nan_mode, false, vectorElement(source, 0, 4), vectorElement(source, 1, 4))
        else if (min_number)
            floatMinNumber(control, nan_mode, false, vectorElement(source, 0, 4), vectorElement(source, 1, 4))
        else
            floatMin(control, nan_mode, false, vectorElement(source, 0, 4), vectorElement(source, 1, 4));
        const right = if (max_number)
            floatMaxNumber(control, nan_mode, false, vectorElement(source, 2, 4), vectorElement(source, 3, 4))
        else if (max_plain)
            floatMax(control, nan_mode, false, vectorElement(source, 2, 4), vectorElement(source, 3, 4))
        else if (min_number)
            floatMinNumber(control, nan_mode, false, vectorElement(source, 2, 4), vectorElement(source, 3, 4))
        else
            floatMin(control, nan_mode, false, vectorElement(source, 2, 4), vectorElement(source, 3, 4));
        const result = if (max_number)
            floatMaxNumber(control, nan_mode, false, left, right)
        else if (max_plain)
            floatMax(control, nan_mode, false, left, right)
        else if (min_number)
            floatMinNumber(control, nan_mode, false, left, right)
        else
            floatMin(control, nan_mode, false, left, right);
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }
};
