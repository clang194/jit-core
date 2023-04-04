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
        if (masked != 0x5f007400 and masked != 0x5f007c00 and masked != 0x7f007400 and masked != 0x7f007c00) {
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
        const result = if (masked == 0x5f007400)
            if (double) signedDoublewordToFloat64(source, fractional_bits) else @as(u64, signedWordToFloat32(@intCast(u32, source), fractional_bits))
        else if (masked == 0x7f007400)
            if (double) unsignedDoublewordToFloat64(self.state.floatControl(), source, fractional_bits) else @as(u64, unsignedWordToFloat32(@intCast(u32, source), fractional_bits))
        else
            try fixedScalarFloat(self, double, source, fractional_bits, masked == 0x7f007c00, .zero);
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarFloatNarrowOdd(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xffbffc00) != 0x7e216800) {
            return false;
        }

        if ((word & 0x00800000) == 0) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const result = @as(u64, float64To32Odd(self.state.floatControl(), source));
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarInverseRootEstimate(self: *Core64, word: u32) Core64Error!bool {
        const half = (word & 0xfffffc00) == 0x7ef9d800;
        const masked = word & 0xffbffc00;
        if (!half and masked != 0x7e21d800 and masked != 0x7ea1d800) {
            return false;
        }

        const double = (word & 0x00800000) != 0;
        const bytes = if (half) @as(usize, 2) else if (double) @as(usize, 8) else @as(usize, 4);
        const source = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = if (half) blk: {
            break :blk @as(u64, float_estimate.inverseRootEstimate16(@intCast(u16, source), control, &status) catch return error.MissingFallback);
        } else if (double) blk: {
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

    pub fn runScalarReciprocalExponent(self: *Core64, word: u32) Core64Error!bool {
        const half = (word & 0xfffffc00) == 0x5ef9f800;
        const masked = word & 0xffbffc00;
        if (!half and masked != 0x5e21f800 and masked != 0x5ea1f800) {
            return false;
        }

        const double = (word & 0x00800000) != 0;
        const bytes = if (half) @as(usize, 2) else if (double) @as(usize, 8) else @as(usize, 4);
        const source = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = if (half) blk: {
            break :blk @as(u64, float_estimate.reciprocalExponent16(@intCast(u16, source), control, &status) catch return error.MissingFallback);
        } else if (double) blk: {
            break :blk float_estimate.reciprocalExponent64(source, control, &status) catch return error.MissingFallback;
        } else blk: {
            break :blk @as(u64, float_estimate.reciprocalExponent32(@intCast(u32, source), control, &status) catch return error.MissingFallback);
        };
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarReciprocalStep(self: *Core64, word: u32) Core64Error!bool {
        const half = (word & 0xffe0fc00) == 0x5e403c00;
        if (!half and (word & 0xffa0fc00) != 0x5e20fc00) {
            return false;
        }

        const double = ((word >> 22) & 1) != 0;
        const bytes = if (half) @as(usize, 2) else if (double) @as(usize, 8) else @as(usize, 4);
        const left = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const right = vectorElement(self.state.readVector(vectorRegFromWord(word >> 16)), 0, bytes);
        const control = self.state.floatControl();
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = if (half)
            @as(u64, float_refine.reciprocalStep16(@intCast(u16, left), @intCast(u16, right), control, &status) catch return error.MissingFallback)
        else if (double)
            float_refine.reciprocalStep64(left, right, control, &status) catch return error.MissingFallback
        else
            @as(u64, float_refine.reciprocalStep32(@intCast(u32, left), @intCast(u32, right), control, &status) catch return error.MissingFallback);
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
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
};
