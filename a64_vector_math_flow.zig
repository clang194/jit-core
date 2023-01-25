const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const float_estimate = @import("float_estimate.zig");
const float_fixed = @import("float_fixed.zig");
const float_fused = @import("float_fused.zig");
const float_refine = @import("float_refine.zig");
const float_rounding = @import("float_rounding.zig");
const float_status = @import("float_status.zig");
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
usingnamespace @import("a64_vector_dot.zig");
usingnamespace @import("a64_count_bits.zig");
usingnamespace @import("a64_memory_bits.zig");

fn fixedScalarFloat(
    self: *Core64,
    double: bool,
    value: u64,
    fractional_bits: usize,
    unsigned_result: bool,
    rounding: float_rounding.RoundingMode,
) Core64Error!u64 {
    const control = self.state.floatControl();
    var status = float_status.FloatStatus.init(self.state.floatStatus());
    const result = if (double)
        float_fixed.fixedFromFloat64(64, value, fractional_bits, unsigned_result, control, rounding, &status)
    else
        float_fixed.fixedFromFloat32(32, @intCast(u32, value), fractional_bits, unsigned_result, control, rounding, &status);
    const converted = result catch return error.MissingFallback;
    self.state.writeFloatStatus(status.raw());
    return converted;
}

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
        if (masked != 0x0e20c400 and masked != 0x0e20d400 and masked != 0x0e20e400 and masked != 0x0e20f400 and masked != 0x0ea0c400 and masked != 0x0ea0d400 and masked != 0x0ea0f400 and masked != 0x2e20c400 and masked != 0x2e20d400 and masked != 0x2e20dc00 and masked != 0x2e20e400 and masked != 0x2e20ec00 and masked != 0x2e20f400 and masked != 0x2e20fc00 and masked != 0x2ea0c400 and masked != 0x2ea0d400 and masked != 0x2ea0e400 and masked != 0x2ea0ec00 and masked != 0x2ea0f400) {
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
        const masked = word & 0xbfa0fc00;
        const subtracting = masked == 0x0ea0cc00;
        if (masked != 0x0e20cc00 and !subtracting) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
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

    pub fn runVectorRootStep(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfa0fc00) != 0x0ea0fc00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = ((word >> 22) & 1) != 0;
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const lanes = (if (full) @as(usize, 16) else @as(usize, 8)) / bytes;
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        var result = a64_state.VectorValue{ .low = 0, .high = 0 };
        var index: usize = 0;
        while (index < lanes) : (index += 1) {
            const left_value = vectorElement(left, index, bytes);
            const right_value = vectorElement(right, index, bytes);
            const refined = if (double)
                float_refine.rootStep64(left_value, right_value, control, &status) catch return error.MissingFallback
            else
                @as(u64, float_refine.rootStep32(@intCast(u32, left_value), @intCast(u32, right_value), control, &status) catch return error.MissingFallback);
            setVectorElement(&result, index, bytes, refined);
        }

        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorReciprocalStep(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfa0fc00) != 0x0e20fc00) {
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
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = reciprocalStepFloatVector(control, &status, double, full, left, right) catch return error.MissingFallback;
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarFloatAbsoluteDifference(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xffa0fc00) != 0x7ea0d400) {
            return false;
        }

        const double = ((word >> 22) & 1) != 0;
        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const mask = if (double) @as(u64, 0x7fffffffffffffff) else @as(u64, 0x7fffffff);
        const left = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const right = vectorElement(self.state.readVector(vectorRegFromWord(word >> 16)), 0, bytes);
        const difference = floatSub(self.state.floatControl(), self.hooks.float_nan_mode, double, left, right) & mask;
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = difference, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarFloatExtendedMultiply(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xffa0fc00) != 0x5e20dc00) {
            return false;
        }

        const double = ((word >> 22) & 1) != 0;
        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const left = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const right = vectorElement(self.state.readVector(vectorRegFromWord(word >> 16)), 0, bytes);
        const result = floatMulExtended(self.state.floatControl(), self.hooks.float_nan_mode, double, left, right);
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarFloatCompareZero(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xffbffc00;
        const greater = masked == 0x5ea0c800;
        const equal = masked == 0x5ea0d800;
        const less = masked == 0x5ea0e800;
        const greater_equal = masked == 0x7ea0c800;
        const less_equal = masked == 0x7ea0d800;
        if (!greater and !equal and !less and !greater_equal and !less_equal) {
            return false;
        }

        const double = ((word >> 22) & 1) != 0;
        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const source = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const result = compareFloatZeroScalar(self.state.floatControl(), double, source, if (equal) .equal else if (greater) .greater else if (greater_equal) .greater_equal else if (less) .less else .less_equal);
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarFloatCompareRegister(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xffa0fc00;
        if (masked != 0x5e20e400 and masked != 0x7e20e400 and masked != 0x7e20ec00 and masked != 0x7ea0e400 and masked != 0x7ea0ec00) {
            return false;
        }

        const double = ((word >> 22) & 1) != 0;
        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const match_value = if (double) ~@as(u64, 0) else @as(u64, 0xffffffff);
        const sign_mask = if (double) @as(u64, 0x7fffffffffffffff) else @as(u64, 0x7fffffff);
        var left = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        var right = vectorElement(self.state.readVector(vectorRegFromWord(word >> 16)), 0, bytes);
        if (masked == 0x7e20ec00 or masked == 0x7ea0ec00) {
            left &= sign_mask;
            right &= sign_mask;
        }

        const matched = if (double) blk: {
            const left_input = floatInput64(self.state.floatControl(), left);
            const right_input = floatInput64(self.state.floatControl(), right);
            const left_value = @bitCast(f64, left_input);
            const right_value = @bitCast(f64, right_input);
            break :blk !isNan64(left_input) and !isNan64(right_input) and if (masked == 0x5e20e400) left_value == right_value else if (masked == 0x7e20e400 or masked == 0x7e20ec00) left_value >= right_value else left_value > right_value;
        } else blk: {
            const left_input = floatInput32(self.state.floatControl(), @intCast(u32, left));
            const right_input = floatInput32(self.state.floatControl(), @intCast(u32, right));
            const left_value = @bitCast(f32, left_input);
            const right_value = @bitCast(f32, right_input);
            break :blk !isNan32(left_input) and !isNan32(right_input) and if (masked == 0x5e20e400) left_value == right_value else if (masked == 0x7e20e400 or masked == 0x7e20ec00) left_value >= right_value else left_value > right_value;
        };
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = if (matched) match_value else 0, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarFloatToInteger(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xffbffc00;
        if (masked != 0x5e21a800 and masked != 0x5e21b800 and masked != 0x5e21c800 and masked != 0x5ea1a800 and masked != 0x5ea1b800 and masked != 0x7e21a800 and masked != 0x7e21b800 and masked != 0x7e21c800 and masked != 0x7ea1a800 and masked != 0x7ea1b800) {
            return false;
        }

        const double = (word & 0x00400000) != 0;
        const source = self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const unsigned_result = (masked & 0x20000000) != 0;
        const rounding = if (masked == 0x5e21a800 or masked == 0x7e21a800)
            float_rounding.RoundingMode.nearest
        else if (masked == 0x5e21b800 or masked == 0x7e21b800)
            float_rounding.RoundingMode.negative
        else if (masked == 0x5e21c800 or masked == 0x7e21c800)
            float_rounding.RoundingMode.nearest_away
        else if (masked == 0x5ea1a800 or masked == 0x7ea1a800)
            float_rounding.RoundingMode.positive
        else
            float_rounding.RoundingMode.zero;
        const result = try fixedScalarFloat(self, double, source, 0, unsigned_result, rounding);
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarFloatToFixed(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff80fc00;
        if (masked != 0x5f007c00 and masked != 0x7f007c00) {
            return false;
        }

        const immh = @intCast(u4, (word >> 19) & 0xf);
        if ((immh & 0xe) == 0 or (immh & 0xe) == 2) {
            return error.ReservedInstruction;
        }

        const double = (immh & 8) != 0;
        const immediate = @as(u8, immh) << 3 | @intCast(u8, (word >> 16) & 7);
        const fractional_bits = (if (double) @as(usize, 128) else @as(usize, 64)) - @as(usize, immediate);
        const source = self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const result = try fixedScalarFloat(self, double, source, fractional_bits, masked == 0x7f007c00, .zero);
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarInverseRootEstimate(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xffbffc00;
        if (masked != 0x7e21d800 and masked != 0x7ea1d800) {
            return false;
        }

        const double = (word & 0x00800000) != 0;
        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const source = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = if (double) blk: {
            break :blk float_estimate.inverseRootEstimate64(source, control, &status) catch return error.MissingFallback;
        } else blk: {
            break :blk @as(u64, float_estimate.inverseRootEstimate32(@intCast(u32, source), control, &status) catch return error.MissingFallback);
        };
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarReciprocalEstimate(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xffbffc00;
        if (masked != 0x5e21d800 and masked != 0x5ea1d800) {
            return false;
        }

        const double = (word & 0x00800000) != 0;
        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const source = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = if (double) blk: {
            break :blk float_estimate.reciprocalEstimate64(source, control, &status) catch return error.MissingFallback;
        } else blk: {
            break :blk @as(u64, float_estimate.reciprocalEstimate32(@intCast(u32, source), control, &status) catch return error.MissingFallback);
        };
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarReciprocalStep(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xffa0fc00) != 0x5e20fc00) {
            return false;
        }

        const double = ((word >> 22) & 1) != 0;
        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const left = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const right = vectorElement(self.state.readVector(vectorRegFromWord(word >> 16)), 0, bytes);
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = if (double)
            float_refine.reciprocalStep64(left, right, control, &status) catch return error.MissingFallback
        else
            @as(u64, float_refine.reciprocalStep32(@intCast(u32, left), @intCast(u32, right), control, &status) catch return error.MissingFallback);
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorInverseRootEstimate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfbffc00) != 0x2ea1d800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = (word & 0x00400000) != 0;
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const lanes = (if (full) @as(usize, 16) else @as(usize, 8)) / bytes;
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        var result = a64_state.VectorValue{ .low = 0, .high = 0 };
        var index: usize = 0;
        while (index < lanes) : (index += 1) {
            const value = vectorElement(source, index, bytes);
            const estimate = if (double)
                float_estimate.inverseRootEstimate64(value, control, &status) catch return error.MissingFallback
            else
                @as(u64, float_estimate.inverseRootEstimate32(@intCast(u32, value), control, &status) catch return error.MissingFallback);
            setVectorElement(&result, index, bytes, estimate);
        }

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
        if ((word & 0xbfbffc00) != 0x2e21d800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = (word & 0x00400000) != 0;
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = reciprocalEstimateFloatVector(control, &status, double, full, source) catch return error.MissingFallback;
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

    pub fn runScalarRootStep(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xffa0fc00) != 0x5ea0fc00) {
            return false;
        }

        const double = ((word >> 22) & 1) != 0;
        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const left = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const right = vectorElement(self.state.readVector(vectorRegFromWord(word >> 16)), 0, bytes);
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = if (double)
            float_refine.rootStep64(left, right, control, &status) catch return error.MissingFallback
        else
            @as(u64, float_refine.rootStep32(@intCast(u32, left), @intCast(u32, right), control, &status) catch return error.MissingFallback);
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
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
            signedDoublewordsToFloatVector(source)
        else
            signedWordsToFloatVector(full, source);
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
            unsignedDoublewordsToFloatVector(self.state.floatControl(), source)
        else
            unsignedWordsToFloatVector(full, source);
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
        const masked = word & 0xbfbffc00;
        const nearest = masked == 0x0e218800;
        const negative = masked == 0x0e219800;
        const positive = masked == 0x0ea18800;
        const zero = masked == 0x0ea19800;
        const nearest_away = masked == 0x2e218800;
        const exact = masked == 0x2e219800;
        const current = masked == 0x2ea19800;
        if (!nearest and !negative and !positive and !zero and !nearest_away and !exact and !current) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = ((word >> 22) & 1) != 0;
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const rounding = if (nearest)
            float_rounding.RoundingMode.nearest
        else if (negative)
            float_rounding.RoundingMode.negative
        else if (positive)
            float_rounding.RoundingMode.positive
        else if (zero)
            float_rounding.RoundingMode.zero
        else if (nearest_away)
            float_rounding.RoundingMode.nearest_away
        else
            self.state.floatControl().rounding();
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = roundIntegralFloatVector(control, &status, double, full, rounding, exact, source) catch return error.MissingFallback;
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
        const result = widenSingleFloatVector(self.state.floatControl(), source, (word & 0x40000000) != 0);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorFloatNarrow(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfbffc00) != 0x0e616800) {
            return false;
        }

        const narrowed = narrowDoubleFloatVector(self.state.floatControl(), self.state.readVector(vectorRegFromWord(word >> 5)));
        const result = if ((word & 0x40000000) != 0)
            a64_state.VectorValue{ .low = self.state.readVector(vectorRegFromWord(word)).low, .high = narrowed }
        else
            a64_state.VectorValue{ .low = narrowed, .high = 0 };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorShiftImmediate(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf80fc00;
        if (masked != 0x0f000400 and masked != 0x0f001400 and masked != 0x0f002400 and masked != 0x0f003400 and masked != 0x0f005400 and masked != 0x0f007400 and masked != 0x0f008400 and masked != 0x0f008c00 and masked != 0x0f009400 and masked != 0x0f009c00 and masked != 0x0f00a400 and masked != 0x2f000400 and masked != 0x2f001400 and masked != 0x2f002400 and masked != 0x2f003400 and masked != 0x2f004400 and masked != 0x2f005400 and masked != 0x2f009400 and masked != 0x2f009c00 and masked != 0x2f00a400) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const immh = @intCast(u4, (word >> 19) & 0xf);
        if (immh == 0) {
            return error.UnallocatedEncoding;
        }
        if (masked == 0x0f008400 or masked == 0x0f008c00 or masked == 0x0f009400 or masked == 0x0f009c00 or masked == 0x2f008400 or masked == 0x2f008c00 or masked == 0x2f009400 or masked == 0x2f009c00) {
            if ((immh & 8) != 0) {
                return error.ReservedInstruction;
            }

            const target_lane = @as(u8, 8) << @intCast(u3, highestSetBit(immh));
            const source_lane = target_lane * 2;
            const immediate = @intCast(u8, (word >> 16) & 0x7f);
            const amount = source_lane - immediate;
            const target_bytes = @intCast(usize, target_lane / 8);
            const source = self.state.readVector(vectorRegFromWord(word >> 5));
            var saturated = false;
            const narrowed = if (masked == 0x2f008400 or masked == 0x2f008c00) blk: {
                const saturated_result = signedSaturatingNarrowUnsignedVectorLanes(source, target_bytes, amount, masked == 0x2f008c00);
                saturated = saturated_result.saturated;
                break :blk saturated_result.value;
            } else if (masked == 0x2f009400 or masked == 0x2f009c00) blk: {
                const saturated_result = unsignedSaturatingNarrowVectorLanes(source, target_bytes, amount, masked == 0x2f009c00);
                saturated = saturated_result.saturated;
                break :blk saturated_result.value;
            } else if (masked == 0x0f009400 or masked == 0x0f009c00) blk: {
                const saturated_result = signedSaturatingNarrowSignedVectorLanes(source, target_bytes, amount, masked == 0x0f009c00);
                saturated = saturated_result.saturated;
                break :blk saturated_result.value;
            } else if (masked == 0x0f008400)
                narrowShiftRightVectorLanes(source, target_bytes, amount)
            else
                narrowRoundedShiftRightVectorLanes(source, target_bytes, amount);
            if (saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            const result = if (full) blk: {
                var target = self.state.readVector(vectorRegFromWord(word));
                target.high = narrowed;
                break :blk target;
            } else a64_state.VectorValue{ .low = narrowed, .high = 0 };
            self.state.writeVector(vectorRegFromWord(word), result);
            self.state.pc +%= 4;
            return true;
        }
        if (masked == 0x0f00a400 or masked == 0x2f00a400) {
            if ((immh & 8) != 0) {
                return error.ReservedInstruction;
            }

            const lane = @as(u8, 8) << @intCast(u3, highestSetBit(immh));
            const immediate = @intCast(u8, (word >> 16) & 0x7f);
            const amount = @intCast(u6, immediate - @intCast(u8, lane));
            const source = self.state.readVector(vectorRegFromWord(word >> 5));
            const half = if (full) source.high else source.low;
            const result = if (masked == 0x0f00a400)
                widenSignedShiftLeftVectorHalf(half, lane, amount)
            else
                widenShiftLeftVectorHalf(half, lane, amount);
            self.state.writeVector(vectorRegFromWord(word), result);
            self.state.pc +%= 4;
            return true;
        }
        if ((immh & 8) != 0 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, highestSetBit(immh));
        const immediate = @intCast(u8, (word >> 16) & 0x7f);
        const signed_right = masked == 0x0f000400 or masked == 0x0f001400;
        const rounded_signed_right = masked == 0x0f002400 or masked == 0x0f003400;
        const rounded_right = masked == 0x2f002400 or masked == 0x2f003400;
        const insert_right = masked == 0x2f004400;
        const signed_saturating_left = masked == 0x0f007400;
        const right = signed_right or rounded_signed_right or rounded_right or insert_right or masked == 0x2f000400 or masked == 0x2f001400;
        const amount = if (right)
            @intCast(u8, @as(u16, lane) * 2 - immediate)
        else
            immediate - @intCast(u8, lane);
        const input = self.state.readVector(vectorRegFromWord(word >> 5));
        if (signed_saturating_left) {
            const shifts = repeatedShiftAmountVector(lane, amount);
            const low = variableSignedSaturatingShiftLeftVectorLanes(input.low, shifts, lane);
            const high = if (full) variableSignedSaturatingShiftLeftVectorLanes(input.high, shifts, lane) else SaturatingShiftResult{ .value = 0, .saturated = false };
            if (low.saturated or high.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = low.value, .high = high.value });
            self.state.pc +%= 4;
            return true;
        }
        if (insert_right or masked == 0x2f005400) {
            const target = self.state.readVector(vectorRegFromWord(word));
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{
                .low = if (insert_right) insertShiftRightVectorLanes(target.low, input.low, lane, amount) else insertShiftLeftVectorLanes(target.low, input.low, lane, amount),
                .high = if (full) if (insert_right) insertShiftRightVectorLanes(target.high, input.high, lane, amount) else insertShiftLeftVectorLanes(target.high, input.high, lane, amount) else 0,
            });
            self.state.pc +%= 4;
            return true;
        }
        const shifted = a64_state.VectorValue{
            .low = if (signed_right) shiftRightSignedVectorLanes(input.low, lane, amount) else if (rounded_signed_right) roundedShiftRightSignedVectorLanes(input.low, lane, amount) else if (rounded_right) roundedShiftRightVectorLanes(input.low, lane, amount) else if (right) shiftRightVectorLanes(input.low, lane, amount) else shiftLeftVectorLanes(input.low, lane, amount),
            .high = if (full) if (signed_right) shiftRightSignedVectorLanes(input.high, lane, amount) else if (rounded_signed_right) roundedShiftRightSignedVectorLanes(input.high, lane, amount) else if (rounded_right) roundedShiftRightVectorLanes(input.high, lane, amount) else if (right) shiftRightVectorLanes(input.high, lane, amount) else shiftLeftVectorLanes(input.high, lane, amount) else 0,
        };
        const result = if (masked == 0x0f001400 or masked == 0x0f003400 or masked == 0x2f001400 or masked == 0x2f003400) blk: {
            const target = self.state.readVector(vectorRegFromWord(word));
            break :blk a64_state.VectorValue{
                .low = addVectorLanes(target.low, shifted.low, lane),
                .high = if (full) addVectorLanes(target.high, shifted.high, lane) else 0,
            };
        } else shifted;
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarShiftImmediate(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff80fc00;
        if (masked != 0x5f000400 and masked != 0x5f001400 and masked != 0x5f002400 and masked != 0x5f003400 and masked != 0x5f005400 and masked != 0x7f000400 and masked != 0x7f001400 and masked != 0x7f002400 and masked != 0x7f003400 and masked != 0x7f004400 and masked != 0x7f005400) {
            return false;
        }

        const immh = @intCast(u4, (word >> 19) & 0xf);
        if ((immh & 8) == 0) {
            return error.ReservedInstruction;
        }

        const immediate = @intCast(u8, (word >> 16) & 0x7f);
        const source = self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const result = if (masked == 0x5f005400)
            source << @intCast(u6, immediate - 64)
        else if (masked == 0x7f005400) blk: {
            const amount = immediate - 64;
            const shifted = source << @intCast(u6, amount);
            const target = self.state.readVector(vectorRegFromWord(word)).low;
            const mask = ~@as(u64, 0) << @intCast(u6, amount);
            break :blk (target & ~mask) | shifted;
        } else if (masked == 0x5f000400) blk: {
            const amount = 128 - @as(u8, immediate);
            const shifted = if (amount == 64)
                if ((source & 0x8000000000000000) == 0) @as(u64, 0) else ~@as(u64, 0)
            else
                @bitCast(u64, @bitCast(i64, source) >> @intCast(u6, amount));
            break :blk shifted;
        } else if (masked == 0x5f001400 or masked == 0x5f002400 or masked == 0x5f003400) blk: {
            const amount = 128 - @as(u8, immediate);
            const shifted = if (amount == 64)
                if ((source & 0x8000000000000000) == 0) @as(u64, 0) else ~@as(u64, 0)
            else
                @bitCast(u64, @bitCast(i64, source) >> @intCast(u6, amount));
            const target = self.state.readVector(vectorRegFromWord(word)).low;
            const rounded = (source >> @intCast(u6, amount - 1)) & 1;
            const extra = if (masked == 0x5f001400) target else if (masked == 0x5f002400) rounded else target +% rounded;
            break :blk shifted +% extra;
        } else blk: {
            const amount = 128 - @as(u8, immediate);
            const shifted = if (amount == 64) @as(u64, 0) else source >> @intCast(u6, amount);
            const target = self.state.readVector(vectorRegFromWord(word)).low;
            if (masked == 0x7f001400) {
                break :blk shifted +% target;
            }
            if (masked == 0x7f002400 or masked == 0x7f003400) {
                const rounded = (source >> @intCast(u6, amount - 1)) & 1;
                break :blk shifted +% if (masked == 0x7f002400) rounded else target +% rounded;
            }
            if (masked == 0x7f004400) {
                const mask = if (amount == 64) @as(u64, 0) else ~@as(u64, 0) >> @intCast(u6, amount);
                break :blk (target & ~mask) | shifted;
            }
            break :blk shifted;
        };
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarVectorArithmetic(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff20fc00;
        const saturating_add = masked == 0x5e200c00;
        const saturating_sub = masked == 0x5e202c00;
        const unsigned_saturating_add = masked == 0x7e200c00;
        const unsigned_saturating_sub = masked == 0x7e202c00;
        const saturating_multiply_high = masked == 0x5e20b400;
        if (!saturating_add and !saturating_sub and !unsigned_saturating_add and !unsigned_saturating_sub and !saturating_multiply_high and masked != 0x5e203400 and masked != 0x5e203c00 and masked != 0x5e204400 and masked != 0x5e205400 and masked != 0x5e208400 and masked != 0x5e208c00 and masked != 0x7e203400 and masked != 0x7e203c00 and masked != 0x7e204400 and masked != 0x7e205400 and masked != 0x7e208400 and masked != 0x7e208c00) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (saturating_multiply_high and (size == 0 or size == 3)) {
            return error.ReservedInstruction;
        }
        if (!saturating_add and !saturating_sub and !unsigned_saturating_add and !unsigned_saturating_sub and !saturating_multiply_high and size != 3) {
            return error.ReservedInstruction;
        }

        const left = self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const right = self.state.readVector(vectorRegFromWord(word >> 16)).low;
        if (saturating_add or saturating_sub or unsigned_saturating_add or unsigned_saturating_sub) {
            const width = @as(u8, 8) << @intCast(u3, size);
            const saturated = if (saturating_add)
                signedSaturatedAdd(width, left, right)
            else if (saturating_sub)
                signedSaturatedSub(width, left, right)
            else if (unsigned_saturating_add)
                unsignedSaturatedAdd(width, left, right)
            else
                unsignedSaturatedSub(width, left, right);
            if (saturated.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = saturated.value, .high = 0 });
            self.state.pc +%= 4;
            return true;
        }
        if (saturating_multiply_high) {
            const width = @as(u8, 8) << @intCast(u3, size);
            const saturated = signedSaturatedDoublingMultiplyHigh(width, left, right);
            if (saturated.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = saturated.value, .high = 0 });
            self.state.pc +%= 4;
            return true;
        }

        const result = if (masked == 0x5e208400)
            left +% right
        else if (masked == 0x7e208400)
            left -% right
        else if (masked == 0x5e203400 and @bitCast(i64, left) > @bitCast(i64, right))
            ~@as(u64, 0)
        else if (masked == 0x5e203c00 and (@bitCast(i64, left) > @bitCast(i64, right) or left == right))
            ~@as(u64, 0)
        else if (masked == 0x7e203400 and left > right)
            ~@as(u64, 0)
        else if (masked == 0x7e203c00 and left >= right)
            ~@as(u64, 0)
        else if (masked == 0x7e208c00 and left == right)
            ~@as(u64, 0)
        else if (masked == 0x5e208c00)
            sharedBitVectorLanes(left, right, 64)
        else if (masked == 0x5e204400)
            variableSignedShiftVectorLanes(left, right, 64)
        else if (masked == 0x5e205400)
            variableRoundedSignedShiftVectorLanes(left, right, 64)
        else if (masked == 0x7e204400)
            variableUnsignedShiftVectorLanes(left, right, 64)
        else if (masked == 0x7e205400)
            variableRoundedUnsignedShiftVectorLanes(left, right, 64)
        else
            0;
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarPairAdd(self: *Core64, word: u32) Core64Error!bool {
        const integer_pair = (word & 0xff20fc00) == 0x5e20bc00;
        const float_pair = (word & 0xffbffc00) == 0x7e30d800;
        const masked_float_pair = word & 0xffbffc00;
        const max_number = masked_float_pair == 0x7e30c800;
        const max_plain = masked_float_pair == 0x7e30f800;
        const min_number = masked_float_pair == 0x7eb0c800;
        const min_plain = masked_float_pair == 0x7eb0f800;
        const float_min_max = max_number or max_plain or min_number or min_plain;
        if (!integer_pair and !float_pair and !float_min_max) {
            return false;
        }

        if (float_pair or float_min_max) {
            const double = ((word >> 22) & 1) != 0;
            const bytes = if (double) @as(usize, 8) else @as(usize, 4);
            const source = self.state.readVector(vectorRegFromWord(word >> 5));
            const left = vectorElement(source, 0, bytes);
            const right = vectorElement(source, 1, bytes);
            const control = self.state.floatControl();
            const nan_mode = self.hooks.float_nan_mode;
            const result = if (float_pair)
                floatAdd(control, nan_mode, double, left, right)
            else if (max_number)
                floatMaxNumber(control, nan_mode, double, left, right)
            else if (max_plain)
                floatMax(control, nan_mode, double, left, right)
            else if (min_number)
                floatMinNumber(control, nan_mode, double, left, right)
            else
                floatMin(control, nan_mode, double, left, right);
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
            self.state.pc +%= 4;
            return true;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size != 3) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = source.low +% source.high, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorAdd(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed_saturating_add = masked == 0x0e200c00;
        const signed_saturating_sub = masked == 0x0e202c00;
        const unsigned_saturating_add = masked == 0x2e200c00;
        const unsigned_saturating_sub = masked == 0x2e202c00;
        const signed_saturating_multiply_high = masked == 0x0e20b400;
        const signed_rounding_saturating_multiply_high = masked == 0x2e20b400;
        if (!signed_saturating_add and !signed_saturating_sub and !unsigned_saturating_add and !unsigned_saturating_sub and !signed_saturating_multiply_high and !signed_rounding_saturating_multiply_high and masked != 0x0e200400 and masked != 0x0e201400 and masked != 0x0e202400 and masked != 0x0e208400 and masked != 0x0e209400 and masked != 0x0e209c00 and masked != 0x2e200400 and masked != 0x2e201400 and masked != 0x2e202400 and masked != 0x2e208400 and masked != 0x2e209400 and masked != 0x2e209c00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if ((signed_saturating_multiply_high or signed_rounding_saturating_multiply_high) and (size == 0 or size == 3)) {
            return error.ReservedInstruction;
        }
        if (masked == 0x2e209c00 and size != 0) {
            return error.ReservedInstruction;
        }
        if (size == 3 and (masked == 0x0e200400 or masked == 0x0e201400 or masked == 0x0e202400 or masked == 0x0e209400 or masked == 0x0e209c00 or masked == 0x2e200400 or masked == 0x2e201400 or masked == 0x2e202400 or masked == 0x2e209400 or !full)) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        if (signed_saturating_add or signed_saturating_sub or unsigned_saturating_add or unsigned_saturating_sub) {
            const low = saturatingVectorLanes(left.low, right.low, lane, signed_saturating_add or signed_saturating_sub, signed_saturating_add or unsigned_saturating_add);
            const high = if (full) saturatingVectorLanes(left.high, right.high, lane, signed_saturating_add or signed_saturating_sub, signed_saturating_add or unsigned_saturating_add) else SaturatingVectorResult{ .value = 0, .saturated = false };
            if (low.saturated or high.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = low.value, .high = high.value });
            self.state.pc +%= 4;
            return true;
        }
        if (signed_saturating_multiply_high) {
            const low = signedSaturatingDoublingMultiplyHighVectorLanes(left.low, right.low, lane);
            const high = if (full) signedSaturatingDoublingMultiplyHighVectorLanes(left.high, right.high, lane) else SaturatingVectorResult{ .value = 0, .saturated = false };
            if (low.saturated or high.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = low.value, .high = high.value });
            self.state.pc +%= 4;
            return true;
        }
        if (signed_rounding_saturating_multiply_high) {
            const parts = signedSaturatingDoublingProductPartsVector(left, right, full, lane);
            if (parts.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            const rounded = a64_state.VectorValue{
                .low = addVectorLanes(parts.high.low, shiftRightVectorLanes(parts.low.low, lane, lane - 1), lane),
                .high = if (full) addVectorLanes(parts.high.high, shiftRightVectorLanes(parts.low.high, lane, lane - 1), lane) else 0,
            };
            self.state.writeVector(vectorRegFromWord(word), rounded);
            self.state.pc +%= 4;
            return true;
        }
        const result = if (masked == 0x2e209c00)
            polynomialByteVector(full, left, right)
        else if (masked == 0x0e209400 or masked == 0x2e209400) blk: {
            const prior = self.state.readVector(vectorRegFromWord(word));
            break :blk a64_state.VectorValue{
                .low = if (masked == 0x0e209400) addVectorLanes(prior.low, multiplyVectorLanes(left.low, right.low, lane), lane) else subtractVectorLanes(prior.low, multiplyVectorLanes(left.low, right.low, lane), lane),
                .high = if (full) if (masked == 0x0e209400) addVectorLanes(prior.high, multiplyVectorLanes(left.high, right.high, lane), lane) else subtractVectorLanes(prior.high, multiplyVectorLanes(left.high, right.high, lane), lane) else 0,
            };
        } else a64_state.VectorValue{
            .low = if (masked == 0x0e200400) signedHalvingAddVectorLanes(left.low, right.low, lane) else if (masked == 0x0e201400) signedRoundingHalvingAddVectorLanes(left.low, right.low, lane) else if (masked == 0x0e202400) signedHalvingSubtractVectorLanes(left.low, right.low, lane) else if (masked == 0x2e200400) halvingAddVectorLanes(left.low, right.low, lane) else if (masked == 0x2e201400) roundingHalvingAddVectorLanes(left.low, right.low, lane) else if (masked == 0x2e202400) halvingSubtractVectorLanes(left.low, right.low, lane) else if (masked == 0x0e208400) addVectorLanes(left.low, right.low, lane) else if (masked == 0x0e209c00) multiplyVectorLanes(left.low, right.low, lane) else subtractVectorLanes(left.low, right.low, lane),
            .high = if (full) if (masked == 0x0e200400) signedHalvingAddVectorLanes(left.high, right.high, lane) else if (masked == 0x0e201400) signedRoundingHalvingAddVectorLanes(left.high, right.high, lane) else if (masked == 0x0e202400) signedHalvingSubtractVectorLanes(left.high, right.high, lane) else if (masked == 0x2e200400) halvingAddVectorLanes(left.high, right.high, lane) else if (masked == 0x2e201400) roundingHalvingAddVectorLanes(left.high, right.high, lane) else if (masked == 0x2e202400) halvingSubtractVectorLanes(left.high, right.high, lane) else if (masked == 0x0e208400) addVectorLanes(left.high, right.high, lane) else if (masked == 0x0e209c00) multiplyVectorLanes(left.high, right.high, lane) else subtractVectorLanes(left.high, right.high, lane) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorMultiplyAddByElement(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf00f400;
        const multiply_only = masked == 0x0f008000;
        const saturating_multiply_high = masked == 0x0f00c000;
        const accumulate = masked == 0x2f000000;
        const subtracting = masked == 0x2f004000;
        if (!multiply_only and !saturating_multiply_high and !accumulate and !subtracting) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 0 or size == 3) {
            return error.UnallocatedEncoding;
        }

        const full = (word & 0x40000000) != 0;
        const bytes = @as(usize, 1) << size;
        const total = if (full) @as(usize, 16) else @as(usize, 8);
        const high = @intCast(usize, (word >> 11) & 1);
        const left_index = @intCast(usize, (word >> 21) & 1);
        const middle_index = @intCast(usize, (word >> 20) & 1);
        const lane_index = if (size == 1)
            (high << 2) | (left_index << 1) | middle_index
        else
            (high << 1) | left_index;
        const element_reg = if (size == 1)
            (word >> 16) & 0xf
        else
            ((word >> 16) & 0xf) | (((word >> 20) & 1) << 4);
        const element = vectorElement(self.state.readVector(vectorRegFromWord(element_reg)), lane_index, bytes);
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const prior = self.state.readVector(vectorRegFromWord(word));
        var result = a64_state.VectorValue{ .low = 0, .high = 0 };
        var saturated_any = false;
        var index: usize = 0;
        while (index < total / bytes) : (index += 1) {
            const left = vectorElement(source, index, bytes);
            const product = if (saturating_multiply_high)
                signedSaturatedDoublingMultiplyHigh(@intCast(u8, bytes * 8), left, element)
            else
                SaturatingIntegerResult{ .value = left *% element, .saturated = false };
            const value = if (accumulate)
                vectorElement(prior, index, bytes) +% product.value
            else if (subtracting)
                vectorElement(prior, index, bytes) -% product.value
            else
                product.value;
            saturated_any = saturated_any or product.saturated;
            setVectorElement(&result, index, bytes, value);
        }
        if (saturated_any) {
            var status = float_status.FloatStatus.init(self.state.floatStatus());
            status.setSaturated(true);
            self.state.writeFloatStatus(status.raw());
        }
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorWideningMultiplyByElement(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf00f400;
        const signed = masked == 0x0f002000 or masked == 0x0f006000 or masked == 0x0f00a000;
        const unsigned = masked == 0x2f002000 or masked == 0x2f006000 or masked == 0x2f00a000;
        if (!signed and !unsigned) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 0 or size == 3) {
            return error.UnallocatedEncoding;
        }

        const upper = (word & 0x40000000) != 0;
        const source_bytes = @as(usize, 1) << size;
        const target_bytes = source_bytes * 2;
        const source_bits = @intCast(u8, source_bytes * 8);
        const high = @intCast(usize, (word >> 11) & 1);
        const left_index = @intCast(usize, (word >> 21) & 1);
        const middle_index = @intCast(usize, (word >> 20) & 1);
        const lane_index = if (size == 1)
            (high << 2) | (left_index << 1) | middle_index
        else
            (high << 1) | left_index;
        const element_reg = if (size == 1)
            (word >> 16) & 0xf
        else
            ((word >> 16) & 0xf) | (((word >> 20) & 1) << 4);
        const source_half = if (upper) self.state.readVector(vectorRegFromWord(word >> 5)).high else self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const element = vectorElement(self.state.readVector(vectorRegFromWord(element_reg)), lane_index, source_bytes);
        const right = if (signed) signExtendRuntime(element, @intCast(u6, source_bits)) else element;
        const source_mask = ones(source_bits);
        const prior = self.state.readVector(vectorRegFromWord(word));
        const accumulating = masked == 0x0f002000 or masked == 0x2f002000;
        const subtracting = masked == 0x0f006000 or masked == 0x2f006000;
        var result = a64_state.VectorValue{ .low = 0, .high = 0 };
        var index: usize = 0;
        while (index < 8 / source_bytes) : (index += 1) {
            const shift = @intCast(u6, index * source_bytes * 8);
            const source = (source_half >> shift) & source_mask;
            const left = if (signed) signExtendRuntime(source, @intCast(u6, source_bits)) else source;
            const product = if (signed) @bitCast(u64, @bitCast(i64, left) *% @bitCast(i64, right)) else left *% right;
            const value = if (accumulating)
                vectorElement(prior, index, target_bytes) +% product
            else if (subtracting)
                vectorElement(prior, index, target_bytes) -% product
            else
                product;
            setVectorElement(&result, index, target_bytes, value);
        }
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorDotProduct(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed = masked == 0x0e009400;
        if (!signed and masked != 0x2e009400) {
            return false;
        }

        if (((word >> 22) & 3) != 2) {
            return error.ReservedInstruction;
        }

        const full = (word & 0x40000000) != 0;
        const target = self.state.readVector(vectorRegFromWord(word));
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        self.state.writeVector(vectorRegFromWord(word), accumulateByteDots(target, left, right, full, signed));
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorDotProductByElement(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf00f400;
        const signed = masked == 0x0f00e000;
        if (!signed and masked != 0x2f00e000) {
            return false;
        }

        if (((word >> 22) & 3) != 2) {
            return error.ReservedInstruction;
        }

        const full = (word & 0x40000000) != 0;
        const lane_index = @intCast(usize, ((word >> 21) & 1) | (((word >> 11) & 1) << 1));
        const element_reg = ((word >> 16) & 0xf) | (((word >> 20) & 1) << 4);
        const target = self.state.readVector(vectorRegFromWord(word));
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(element_reg));
        self.state.writeVector(vectorRegFromWord(word), accumulateByteDotsWithLane(target, left, right, full, lane_index, signed));
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorFloatMultiplyByElement(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf00f400;
        const multiply_only = masked == 0x0f009000;
        const accumulate = masked == 0x0f001000;
        const subtract = masked == 0x0f005000;
        if (!multiply_only and !accumulate and !subtract) {
            return false;
        }

        const double = (word & 0x00800000) != 0;
        const full = (word & 0x40000000) != 0;
        const left_index = @intCast(usize, (word >> 22) & 1);
        const middle_index = @intCast(usize, (word >> 21) & 1);
        const high = @intCast(usize, (word >> 11) & 1);
        if (double and left_index != 0) {
            return error.UnallocatedEncoding;
        }
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
        const lane_index = if (double) high else (high << 1) | left_index;
        const element_reg = ((word >> 16) & 0xf) | (middle_index << 4);
        const element = vectorElement(self.state.readVector(vectorRegFromWord(element_reg)), lane_index, bytes);
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const control = self.state.floatControl();
        const nan_mode = self.hooks.float_nan_mode;
        const prior = self.state.readVector(vectorRegFromWord(word));
        var result = a64_state.VectorValue{ .low = 0, .high = 0 };
        if (multiply_only) {
            var index: usize = 0;
            while (index < lanes) : (index += 1) {
                setVectorElement(&result, index, bytes, floatMul(control, nan_mode, double, vectorElement(source, index, bytes), element));
            }
        } else {
            const fused_control = effectiveFloatControl(control, nan_mode);
            var status = float_status.FloatStatus.init(self.state.floatStatus());
            var index: usize = 0;
            while (index < lanes) : (index += 1) {
                const addend = vectorElement(prior, index, bytes);
                const left = vectorElement(source, index, bytes);
                const adjusted_left = if (subtract) negateFloat(double, left) else left;
                const value = if (double)
                    float_fused.mulAdd64(addend, adjusted_left, element, fused_control, &status) catch return error.MissingFallback
                else
                    @as(u64, float_fused.mulAdd32(@intCast(u32, addend), @intCast(u32, adjusted_left), @intCast(u32, element), fused_control, &status) catch return error.MissingFallback);
                setVectorElement(&result, index, bytes, value);
            }
            self.state.writeFloatStatus(status.raw());
        }
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarFloatMultiplyByElement(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff00f400;
        const multiply_only = masked == 0x5f009000;
        const accumulate = masked == 0x5f001000;
        const subtract = masked == 0x5f005000;
        if (!multiply_only and !accumulate and !subtract) {
            return false;
        }

        const double = (word & 0x00800000) != 0;
        const left_index = @intCast(usize, (word >> 22) & 1);
        const middle_index = @intCast(usize, (word >> 21) & 1);
        const high = @intCast(usize, (word >> 11) & 1);
        if (double and left_index != 0) {
            return error.UnallocatedEncoding;
        }

        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const lane_index = if (double) high else (high << 1) | left_index;
        const element_reg = ((word >> 16) & 0xf) | (middle_index << 4);
        const source = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const element = vectorElement(self.state.readVector(vectorRegFromWord(element_reg)), lane_index, bytes);
        const result = if (multiply_only)
            floatMul(self.state.floatControl(), self.hooks.float_nan_mode, double, source, element)
        else blk: {
            const control = effectiveFloatControl(self.state.floatControl(), self.hooks.float_nan_mode);
            var status = float_status.FloatStatus.init(self.state.floatStatus());
            const addend = vectorElement(self.state.readVector(vectorRegFromWord(word)), 0, bytes);
            const left = if (subtract) negateFloat(double, source) else source;
            const value = if (double)
                float_fused.mulAdd64(addend, left, element, control, &status) catch return error.MissingFallback
            else
                @as(u64, float_fused.mulAdd32(@intCast(u32, addend), @intCast(u32, left), @intCast(u32, element), control, &status) catch return error.MissingFallback);
            self.state.writeFloatStatus(status.raw());
            break :blk value;
        };
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarMultiplyHighByElement(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff00f400;
        if (masked != 0x5f00c000) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 0 or size == 3) {
            return error.UnallocatedEncoding;
        }

        const bytes = @as(usize, 1) << size;
        const high = @intCast(usize, (word >> 11) & 1);
        const left_index = @intCast(usize, (word >> 21) & 1);
        const middle_index = @intCast(usize, (word >> 20) & 1);
        const lane_index = if (size == 1)
            (high << 2) | (left_index << 1) | middle_index
        else
            (high << 1) | left_index;
        const element_reg = if (size == 1)
            (word >> 16) & 0xf
        else
            ((word >> 16) & 0xf) | (((word >> 20) & 1) << 4);
        const source = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const element = vectorElement(self.state.readVector(vectorRegFromWord(element_reg)), lane_index, bytes);
        const result = signedSaturatedDoublingMultiplyHigh(@intCast(u8, bytes * 8), source, element);
        if (result.saturated) {
            var status = float_status.FloatStatus.init(self.state.floatStatus());
            status.setSaturated(true);
            self.state.writeFloatStatus(status.raw());
        }
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result.value, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorWideningArithmetic(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed_difference = masked == 0x0e205000 or masked == 0x0e207000;
        const signed_multiply_accumulate = masked == 0x0e208000;
        const signed_multiply_subtract = masked == 0x0e20a000;
        const signed_multiply_long = masked == 0x0e20c000;
        const signed_saturating_multiply_long = masked == 0x0e20d000;
        const unsigned_multiply_accumulate = masked == 0x2e208000;
        const unsigned_multiply_subtract = masked == 0x2e20a000;
        const unsigned_multiply_long = masked == 0x2e20c000;
        const polynomial_wide = masked == 0x0e20e000;
        const multiplying_long = signed_multiply_accumulate or signed_multiply_subtract or signed_multiply_long or signed_saturating_multiply_long or unsigned_multiply_accumulate or unsigned_multiply_subtract or unsigned_multiply_long;
        const signed = masked == 0x0e200000 or masked == 0x0e201000 or masked == 0x0e202000 or masked == 0x0e203000 or signed_difference or signed_multiply_accumulate or signed_multiply_subtract or signed_multiply_long or signed_saturating_multiply_long;
        const subtracting = masked == 0x0e202000 or masked == 0x0e203000 or masked == 0x2e202000 or masked == 0x2e203000;
        const widening_source_pair = masked == 0x0e200000 or masked == 0x0e202000 or masked == 0x2e200000 or masked == 0x2e202000;
        const accumulating_difference = masked == 0x0e205000 or masked == 0x2e205000;
        const absolute_difference = masked == 0x0e207000 or masked == 0x2e207000 or accumulating_difference;
        if (!signed and masked != 0x2e201000 and masked != 0x2e203000 and !widening_source_pair and !absolute_difference and !multiplying_long and !polynomial_wide) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (polynomial_wide and (size == 1 or size == 2)) {
            return error.ReservedInstruction;
        }
        if (!polynomial_wide and size == 3) {
            return error.ReservedInstruction;
        }
        if (signed_saturating_multiply_long and size == 0) {
            return error.ReservedInstruction;
        }

        const upper = (word & 0x40000000) != 0;
        const base = self.state.readVector(vectorRegFromWord(word >> 5));
        const addend = self.state.readVector(vectorRegFromWord(word >> 16));
        if (polynomial_wide) {
            const result = if (size == 3)
                polynomialWideWordProduct(if (upper) base.high else base.low, if (upper) addend.high else addend.low)
            else
                polynomialWideByteVector(upper, base, addend);
            self.state.writeVector(vectorRegFromWord(word), result);
            self.state.pc +%= 4;
            return true;
        }

        const source_bytes = @as(usize, 1) << size;
        const target_bytes = source_bytes * 2;
        const source_bits = @intCast(u8, source_bytes * 8);
        const source_mask = ones(source_bits);
        const addend_half = if (upper) addend.high else addend.low;
        const base_half = if (upper) base.high else base.low;
        if (signed_saturating_multiply_long) {
            const saturated = signedSaturatingDoublingLongProductHalf(base_half, addend_half, source_bits);
            if (saturated.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), saturated.value);
            self.state.pc +%= 4;
            return true;
        }
        var result = a64_state.VectorValue{ .low = 0, .high = 0 };
        var index: usize = 0;
        while (index < 8 / source_bytes) : (index += 1) {
            const shift = @intCast(u6, index * source_bytes * 8);
            const raw_left = (base_half >> shift) & source_mask;
            const left = if (widening_source_pair or absolute_difference or signed_multiply_accumulate or signed_multiply_subtract or signed_multiply_long or unsigned_multiply_accumulate or unsigned_multiply_subtract or unsigned_multiply_long) if (signed) signExtendRuntime(raw_left, @intCast(u6, source_bits)) else raw_left else vectorElement(base, index, target_bytes);
            const raw = (addend_half >> shift) & source_mask;
            const right = if (signed) signExtendRuntime(raw, @intCast(u6, source_bits)) else raw;
            const difference = if (signed_difference) blk: {
                const signed_left = @bitCast(i64, left);
                const signed_right = @bitCast(i64, right);
                break :blk @bitCast(u64, if (signed_left >= signed_right) signed_left - signed_right else signed_right - signed_left);
            } else if (left >= right) left - right else right - left;
            const product = if (signed) @bitCast(u64, @bitCast(i64, left) *% @bitCast(i64, right)) else left *% right;
            const value = if (signed_multiply_accumulate or unsigned_multiply_accumulate) vectorElement(self.state.readVector(vectorRegFromWord(word)), index, target_bytes) +% product else if (signed_multiply_subtract or unsigned_multiply_subtract) vectorElement(self.state.readVector(vectorRegFromWord(word)), index, target_bytes) -% product else if (signed_multiply_long or unsigned_multiply_long) product else if (accumulating_difference) vectorElement(self.state.readVector(vectorRegFromWord(word)), index, target_bytes) +% difference else if (absolute_difference) difference else if (subtracting) left -% right else left +% right;
            setVectorElement(&result, index, target_bytes, value);
        }
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorHighNarrowArithmetic(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const adding = masked == 0x0e204000;
        const subtracting = masked == 0x0e206000;
        const rounded_adding = masked == 0x2e204000;
        const rounded_subtracting = masked == 0x2e206000;
        if (!adding and !subtracting and !rounded_adding and !rounded_subtracting) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3) {
            return error.ReservedInstruction;
        }

        const upper = (word & 0x40000000) != 0;
        const target_bytes = @as(usize, 1) << size;
        const wide_bytes = target_bytes * 2;
        const target_bits = @intCast(u8, target_bytes * 8);
        const wide_mask = ones(target_bits * 2);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        var narrowed_value = a64_state.VectorValue{ .low = 0, .high = 0 };
        var index: usize = 0;
        while (index < 8 / target_bytes) : (index += 1) {
            const wide_left = vectorElement(left, index, wide_bytes);
            const wide_right = vectorElement(right, index, wide_bytes);
            var combined = (if (adding or rounded_adding) wide_left +% wide_right else wide_left -% wide_right) & wide_mask;
            if (rounded_adding or rounded_subtracting) {
                combined = (combined +% (@as(u64, 1) << @intCast(u6, target_bits - 1))) & wide_mask;
            }
            setVectorElement(&narrowed_value, index, target_bytes, combined >> @intCast(u6, target_bits));
        }

        const result = if (upper) a64_state.VectorValue{ .low = self.state.readVector(vectorRegFromWord(word)).low, .high = narrowed_value.low } else a64_state.VectorValue{ .low = narrowed_value.low, .high = 0 };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorPairAdd(self: *Core64, word: u32) Core64Error!bool {
        const pattern = word & 0xbf20fc00;
        const paired = pattern == 0x0e20bc00;
        const wide_signed = pattern == 0x0e202800;
        const wide_unsigned = pattern == 0x2e202800;
        const accumulating_signed = pattern == 0x0e203800;
        const accumulating_unsigned = pattern == 0x2e203800;
        const wide = wide_signed or wide_unsigned or accumulating_signed or accumulating_unsigned;
        if (!paired and !wide) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if ((wide and size == 3) or (paired and size == 3 and !full)) {
            return error.ReservedInstruction;
        }

        if (wide) {
            const bytes = @as(usize, 1) << @intCast(u6, size);
            const total = if (full) @as(usize, 16) else @as(usize, 8);
            const source = self.state.readVector(vectorRegFromWord(word >> 5));
            var result = pairwiseAddWideVector(source, bytes, total, wide_signed or accumulating_signed);
            if (accumulating_signed or accumulating_unsigned) {
                const target = self.state.readVector(vectorRegFromWord(word));
                const lane = @as(u8, 16) << @intCast(u3, size);
                result = a64_state.VectorValue{
                    .low = addVectorLanes(target.low, result.low, lane),
                    .high = if (full) addVectorLanes(target.high, result.high, lane) else 0,
                };
            }
            self.state.writeVector(vectorRegFromWord(word), result);
            self.state.pc +%= 4;
            return true;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = if (full)
            a64_state.VectorValue{
                .low = pairVectorHalves(left.low, left.high, lane),
                .high = pairVectorHalves(right.low, right.high, lane),
            }
        else
            a64_state.VectorValue{
                .low = pairVectorHalves(left.low, right.low, lane),
                .high = 0,
            };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorPairExtrema(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed_max = masked == 0x0e20a400;
        const signed_min = masked == 0x0e20ac00;
        const unsigned_max = masked == 0x2e20a400;
        const unsigned_min = masked == 0x2e20ac00;
        if (!signed_max and !signed_min and !unsigned_max and !unsigned_min) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3) {
            return error.ReservedInstruction;
        }

        const full = (word & 0x40000000) != 0;
        const lane = @as(u8, 8) << @intCast(u3, size);
        const signed = signed_max or signed_min;
        const maximum = signed_max or unsigned_max;
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = if (full)
            a64_state.VectorValue{
                .low = pairVectorExtrema(left.low, left.high, lane, signed, maximum),
                .high = pairVectorExtrema(right.low, right.high, lane, signed, maximum),
            }
        else
            a64_state.VectorValue{
                .low = pairVectorExtrema(left.low, right.low, lane, signed, maximum),
                .high = 0,
            };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorEqual(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf20fc00) != 0x2e208c00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = a64_state.VectorValue{
            .low = equalVectorLanes(left.low, right.low, lane),
            .high = if (full) equalVectorLanes(left.high, right.high, lane) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorSharedBitCompare(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf20fc00) != 0x0e208c00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = a64_state.VectorValue{
            .low = sharedBitVectorLanes(left.low, right.low, lane),
            .high = if (full) sharedBitVectorLanes(left.high, right.high, lane) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorGreaterSigned(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const strict = masked == 0x0e203400;
        const inclusive = masked == 0x0e203c00;
        if (!strict and !inclusive) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = a64_state.VectorValue{
            .low = greaterSignedVectorLanes(left.low, right.low, lane, inclusive),
            .high = if (full) greaterSignedVectorLanes(left.high, right.high, lane, inclusive) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorGreaterUnsigned(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const strict = masked == 0x2e203400;
        const inclusive = masked == 0x2e203c00;
        if (!strict and !inclusive) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = a64_state.VectorValue{
            .low = greaterUnsignedVectorLanes(left.low, right.low, lane, inclusive),
            .high = if (full) greaterUnsignedVectorLanes(left.high, right.high, lane, inclusive) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorUnsignedShift(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed = masked == 0x0e204400;
        const signed_saturating = masked == 0x0e204c00;
        const rounded_signed = masked == 0x0e205400;
        const rounded_unsigned = masked == 0x2e205400;
        if (!signed and !signed_saturating and !rounded_signed and masked != 0x2e204400 and !rounded_unsigned) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        if (signed_saturating) {
            const low = variableSignedSaturatingShiftLeftVectorLanes(left.low, right.low, lane);
            const high = if (full) variableSignedSaturatingShiftLeftVectorLanes(left.high, right.high, lane) else SaturatingShiftResult{ .value = 0, .saturated = false };
            if (low.saturated or high.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = low.value, .high = high.value });
            self.state.pc +%= 4;
            return true;
        }
        const result = a64_state.VectorValue{
            .low = if (signed) variableSignedShiftVectorLanes(left.low, right.low, lane) else if (rounded_signed) variableRoundedSignedShiftVectorLanes(left.low, right.low, lane) else if (rounded_unsigned) variableRoundedUnsignedShiftVectorLanes(left.low, right.low, lane) else variableUnsignedShiftVectorLanes(left.low, right.low, lane),
            .high = if (full) if (signed) variableSignedShiftVectorLanes(left.high, right.high, lane) else if (rounded_signed) variableRoundedSignedShiftVectorLanes(left.high, right.high, lane) else if (rounded_unsigned) variableRoundedUnsignedShiftVectorLanes(left.high, right.high, lane) else variableUnsignedShiftVectorLanes(left.high, right.high, lane) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorMinMax(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed_max = masked == 0x0e206400;
        const signed_min = masked == 0x0e206c00;
        const unsigned_max = masked == 0x2e206400;
        const unsigned_min = masked == 0x2e206c00;
        if (!signed_max and !signed_min and !unsigned_max and !unsigned_min) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3) {
            return error.ReservedInstruction;
        }

        const full = (word & 0x40000000) != 0;
        const lane = @as(u8, 8) << @intCast(u3, size);
        const signed = signed_max or signed_min;
        const maximum = signed_max or unsigned_max;
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = a64_state.VectorValue{
            .low = minMaxVectorLanes(left.low, right.low, lane, signed, maximum),
            .high = if (full) minMaxVectorLanes(left.high, right.high, lane, signed, maximum) else 0,
        };
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

    pub fn runVectorAcrossMinMax(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf3ffc00;
        const signed_max = masked == 0x0e30a800;
        const signed_min = masked == 0x0e31a800;
        const unsigned_max = masked == 0x2e30a800;
        const unsigned_min = masked == 0x2e31a800;
        if (!signed_max and !signed_min and !unsigned_max and !unsigned_min) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        const full = (word & 0x40000000) != 0;
        if ((size == 2 and !full) or size == 3) {
            return error.ReservedInstruction;
        }

        const bytes = @as(usize, 1) << @intCast(u3, size);
        const lanes = (if (full) @as(usize, 16) else @as(usize, 8)) / bytes;
        const signed = signed_max or signed_min;
        const maximum = signed_max or unsigned_max;
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        var value = if (signed) signExtendRuntime(vectorElement(source, 0, bytes), @intCast(u6, bytes * 8)) else vectorElement(source, 0, bytes);
        var index: usize = 1;
        while (index < lanes) : (index += 1) {
            const element = if (signed) signExtendRuntime(vectorElement(source, index, bytes), @intCast(u6, bytes * 8)) else vectorElement(source, index, bytes);
            value = if (maximum) integerMaximum(false, signed, value, element) else integerMinimum(false, signed, value, element);
        }

        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = value & ones(@intCast(u8, bytes * 8)), .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorAcrossAdd(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf3ffc00;
        const narrow = masked == 0x0e31b800;
        const signed_wide = masked == 0x0e303800;
        const unsigned_wide = masked == 0x2e303800;
        const wide = signed_wide or unsigned_wide;
        if (!narrow and !wide) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        const full = (word & 0x40000000) != 0;
        if ((size == 2 and !full) or size == 3) {
            return error.ReservedInstruction;
        }

        const bytes = @as(usize, 1) << @intCast(u3, size);
        const lanes = (if (full) @as(usize, 16) else @as(usize, 8)) / bytes;
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        var sum: u64 = 0;
        var index: usize = 0;
        while (index < lanes) : (index += 1) {
            const element = vectorElement(source, index, bytes);
            sum +%= if (signed_wide) signExtendRuntime(element, @intCast(u6, bytes * 8)) else element;
        }

        const result = if (wide)
            if (size == 0) sum & 0xffff else if (size == 1) sum & 0xffffffff else sum
        else
            sum & if (size == 0) @as(u64, 0xff) else if (size == 1) @as(u64, 0xffff) else @as(u64, 0xffffffff);
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorDifference(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed_plain = masked == 0x0e207400;
        const plain = signed_plain or masked == 0x2e207400;
        const signed_accumulating = masked == 0x0e207c00;
        const accumulating = signed_accumulating or masked == 0x2e207c00;
        if (!plain and !accumulating) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3) {
            return error.ReservedInstruction;
        }

        const full = (word & 0x40000000) != 0;
        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const difference = a64_state.VectorValue{
            .low = if (signed_plain or signed_accumulating) differenceSignedVectorLanes(left.low, right.low, lane) else differenceUnsignedVectorLanes(left.low, right.low, lane),
            .high = if (full) if (signed_plain or signed_accumulating) differenceSignedVectorLanes(left.high, right.high, lane) else differenceUnsignedVectorLanes(left.high, right.high, lane) else 0,
        };
        const result = if (plain) difference else blk: {
            const prior = self.state.readVector(vectorRegFromWord(word));
            break :blk a64_state.VectorValue{
                .low = addVectorLanes(prior.low, difference.low, lane),
                .high = if (full) addVectorLanes(prior.high, difference.high, lane) else 0,
            };
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }
};
