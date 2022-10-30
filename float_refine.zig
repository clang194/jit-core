const a64_float_nan = @import("a64_float_nan.zig");
const float_control = @import("float_control.zig");
const float_exception = @import("float_exception.zig");
const float_format = @import("float_format.zig");
const float_fused = @import("float_fused.zig");
const float_parts = @import("float_parts.zig");
const float_status = @import("float_status.zig");

const three_parts = float_parts.scaledParts(false, 0, 3);
const two_parts = float_parts.scaledParts(false, 0, 2);

pub fn rootStep32(left: u32, right: u32, control: float_control.Control, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u32 {
    const adjusted_left = left ^ float_format.Binary32.sign_mask;
    const left_analysis = try float_parts.splitFloat32(adjusted_left, control, status);
    const right_analysis = try float_parts.splitFloat32(right, control, status);

    const maybe_nan = try a64_float_nan.processPairNan32(control, adjusted_left, right, status);
    if (maybe_nan) |nan| {
        return nan;
    }

    const left_infinity = left_analysis.kind == .infinity;
    const right_infinity = right_analysis.kind == .infinity;
    const left_zero = left_analysis.kind == .zero;
    const right_zero = right_analysis.kind == .zero;
    if ((left_infinity and right_zero) or (left_zero and right_infinity)) {
        return float_format.Binary32.finite(false, -1, 3);
    }
    if (left_infinity or right_infinity) {
        return float_format.Binary32.infinity(left_analysis.negative != right_analysis.negative);
    }

    var result = float_fused.fusedParts(three_parts, left_analysis.parts, right_analysis.parts);
    result.exponent -= 1;
    if (result.significand == 0) {
        return float_format.Binary32.zero(control.rounding() == .negative);
    }
    return try float_parts.roundFloat32(result, control, status);
}

pub fn rootStep64(left: u64, right: u64, control: float_control.Control, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u64 {
    const adjusted_left = left ^ float_format.Binary64.sign_mask;
    const left_analysis = try float_parts.splitFloat64(adjusted_left, control, status);
    const right_analysis = try float_parts.splitFloat64(right, control, status);

    const maybe_nan = try a64_float_nan.processPairNan64(control, adjusted_left, right, status);
    if (maybe_nan) |nan| {
        return nan;
    }

    const left_infinity = left_analysis.kind == .infinity;
    const right_infinity = right_analysis.kind == .infinity;
    const left_zero = left_analysis.kind == .zero;
    const right_zero = right_analysis.kind == .zero;
    if ((left_infinity and right_zero) or (left_zero and right_infinity)) {
        return float_format.Binary64.finite(false, -1, 3);
    }
    if (left_infinity or right_infinity) {
        return float_format.Binary64.infinity(left_analysis.negative != right_analysis.negative);
    }

    var result = float_fused.fusedParts(three_parts, left_analysis.parts, right_analysis.parts);
    result.exponent -= 1;
    if (result.significand == 0) {
        return float_format.Binary64.zero(control.rounding() == .negative);
    }
    return try float_parts.roundFloat64(result, control, status);
}

pub fn reciprocalStep32(left: u32, right: u32, control: float_control.Control, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u32 {
    const adjusted_left = left ^ float_format.Binary32.sign_mask;
    const left_analysis = try float_parts.splitFloat32(adjusted_left, control, status);
    const right_analysis = try float_parts.splitFloat32(right, control, status);

    const maybe_nan = try a64_float_nan.processPairNan32(control, adjusted_left, right, status);
    if (maybe_nan) |nan| {
        return nan;
    }

    const left_infinity = left_analysis.kind == .infinity;
    const right_infinity = right_analysis.kind == .infinity;
    const left_zero = left_analysis.kind == .zero;
    const right_zero = right_analysis.kind == .zero;
    if ((left_infinity and right_zero) or (left_zero and right_infinity)) {
        return float_format.Binary32.finite(false, 0, 2);
    }
    if (left_infinity or right_infinity) {
        return float_format.Binary32.infinity(left_analysis.negative != right_analysis.negative);
    }

    const result = float_fused.fusedParts(two_parts, left_analysis.parts, right_analysis.parts);
    if (result.significand == 0) {
        return float_format.Binary32.zero(control.rounding() == .negative);
    }
    return try float_parts.roundFloat32(result, control, status);
}

pub fn reciprocalStep64(left: u64, right: u64, control: float_control.Control, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u64 {
    const adjusted_left = left ^ float_format.Binary64.sign_mask;
    const left_analysis = try float_parts.splitFloat64(adjusted_left, control, status);
    const right_analysis = try float_parts.splitFloat64(right, control, status);

    const maybe_nan = try a64_float_nan.processPairNan64(control, adjusted_left, right, status);
    if (maybe_nan) |nan| {
        return nan;
    }

    const left_infinity = left_analysis.kind == .infinity;
    const right_infinity = right_analysis.kind == .infinity;
    const left_zero = left_analysis.kind == .zero;
    const right_zero = right_analysis.kind == .zero;
    if ((left_infinity and right_zero) or (left_zero and right_infinity)) {
        return float_format.Binary64.finite(false, 0, 2);
    }
    if (left_infinity or right_infinity) {
        return float_format.Binary64.infinity(left_analysis.negative != right_analysis.negative);
    }

    const result = float_fused.fusedParts(two_parts, left_analysis.parts, right_analysis.parts);
    if (result.significand == 0) {
        return float_format.Binary64.zero(control.rounding() == .negative);
    }
    return try float_parts.roundFloat64(result, control, status);
}
