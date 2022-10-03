const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const float_exception = @import("float_exception.zig");
const float_parts = @import("float_parts.zig");
const float_residue = @import("float_residue.zig");
const float_rounding = @import("float_rounding.zig");
const float_status = @import("float_status.zig");

fn maskForWidth(width: usize) u64 {
    if (width == 0) {
        return 0;
    }
    if (width >= 64) {
        return ~@as(u64, 0);
    }
    return (@as(u64, 1) << @intCast(u6, width)) - 1;
}

fn signLimit(width: usize) u64 {
    return @as(u64, 1) << @intCast(u6, width - 1);
}

fn highIndex(value: u64) i32 {
    return @intCast(i32, 63 - @clz(u64, value));
}

fn scaledShift(value: u64, exponent: i32) u64 {
    if (exponent >= 0) {
        return bits.shiftLeft64(value, exponent);
    }
    return bits.signedShiftRight64(value, -exponent);
}

fn shouldRaise(mode: float_rounding.RoundingMode, residue: float_residue.ShiftResidue, shifted: u64) bool {
    return switch (mode) {
        .nearest => residue == .above_half or (residue == .half and bits.getBit64(shifted, 0)),
        .positive => residue != .zero,
        .negative => false,
        .nearest_away => residue == .above_half or (residue == .half and !bits.topBit64(shifted)),
        .zero => residue != .zero and bits.topBit64(shifted),
    };
}

fn fixedFromParts(
    integer_bits: usize,
    analysis: float_parts.FloatAnalysis,
    fractional_bits: usize,
    unsigned_result: bool,
    control: a64_state.FloatControl,
    mode: float_rounding.RoundingMode,
    status: *float_status.FloatStatus,
) float_exception.FloatExceptionError!u64 {
    if (analysis.kind == .quiet_nan or analysis.kind == .signaling_nan) {
        try float_exception.processFloatException(.invalid_operation, control, status);
    }

    if (analysis.parts.significand == 0) {
        return 0;
    }

    if (analysis.negative and unsigned_result) {
        try float_exception.processFloatException(.invalid_operation, control, status);
        return 0;
    }

    var parts = analysis.parts;
    parts.exponent += @intCast(i32, fractional_bits);

    const signed_magnitude = if (analysis.negative) bits.negate64(parts.significand) else parts.significand;
    const residue = float_residue.classifyRightShiftResidue64(signed_magnitude, -parts.exponent);
    var shifted = scaledShift(signed_magnitude, parts.exponent);
    const raise = shouldRaise(mode, residue, shifted);

    if (raise) {
        shifted +%= 1;
    }

    const rounded_significand = parts.significand +% if (raise) @as(u64, 1) else @as(u64, 0);
    const min_exponent = @intCast(i32, integer_bits) - highIndex(rounded_significand) - if (unsigned_result) @as(i32, 0) else @as(i32, 1);
    if (parts.exponent >= min_exponent) {
        if (unsigned_result or !analysis.negative) {
            try float_exception.processFloatException(.invalid_operation, control, status);
            return maskForWidth(integer_bits - if (unsigned_result) @as(usize, 0) else @as(usize, 1));
        }

        const lowest = bits.negate64(signLimit(integer_bits));
        if (!(parts.exponent == min_exponent and shifted == lowest)) {
            try float_exception.processFloatException(.invalid_operation, control, status);
            return signLimit(integer_bits);
        }
    }

    if (residue != .zero) {
        try float_exception.processFloatException(.inexact, control, status);
    }

    return shifted & maskForWidth(integer_bits);
}

pub fn fixedFromFloat32(
    integer_bits: usize,
    value: u32,
    fractional_bits: usize,
    unsigned_result: bool,
    control: a64_state.FloatControl,
    mode: float_rounding.RoundingMode,
    status: *float_status.FloatStatus,
) float_exception.FloatExceptionError!u64 {
    const analysis = try float_parts.splitFloat32(value, control, status);
    return fixedFromParts(integer_bits, analysis, fractional_bits, unsigned_result, control, mode, status);
}

pub fn fixedFromFloat64(
    integer_bits: usize,
    value: u64,
    fractional_bits: usize,
    unsigned_result: bool,
    control: a64_state.FloatControl,
    mode: float_rounding.RoundingMode,
    status: *float_status.FloatStatus,
) float_exception.FloatExceptionError!u64 {
    const analysis = try float_parts.splitFloat64(value, control, status);
    return fixedFromParts(integer_bits, analysis, fractional_bits, unsigned_result, control, mode, status);
}
