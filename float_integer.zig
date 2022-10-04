const a64_float_nan = @import("a64_float_nan.zig");
const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const float_exception = @import("float_exception.zig");
const float_format = @import("float_format.zig");
const float_parts = @import("float_parts.zig");
const float_residue = @import("float_residue.zig");
const float_rounding = @import("float_rounding.zig");
const float_status = @import("float_status.zig");

fn moveInteger(value: u64, exponent: i32) u64 {
    if (exponent >= 0) {
        return bits.shiftLeft64(value, exponent);
    }
    return bits.signedShiftRight64(value, -exponent);
}

fn shouldIncrease(mode: float_rounding.RoundingMode, residue: float_residue.ShiftResidue, shifted: u64) bool {
    return switch (mode) {
        .nearest => residue == .above_half or (residue == .half and bits.getBit64(shifted, 0)),
        .positive => residue != .zero,
        .negative => false,
        .nearest_away => residue == .above_half or (residue == .half and !bits.topBit64(shifted)),
        .zero => residue != .zero and bits.topBit64(shifted),
    };
}

fn signedMagnitude(negative: bool, value: u64) u64 {
    return if (negative) bits.negate64(value) else value;
}

fn unsignedMagnitude(value: u64) u64 {
    return if (bits.topBit64(value)) bits.negate64(value) else value;
}

fn roundParts32(
    value: u32,
    analysis: float_parts.FloatAnalysis,
    control: a64_state.FloatControl,
    mode: float_rounding.RoundingMode,
    exact: bool,
    status: *float_status.FloatStatus,
) float_exception.FloatExceptionError!u32 {
    switch (analysis.kind) {
        .quiet_nan, .signaling_nan => return try a64_float_nan.processNan32(control, value, status),
        .infinity => return float_format.Binary32.infinity(analysis.negative),
        .zero => return float_format.Binary32.zero(analysis.negative),
        .finite => {},
    }

    if (analysis.parts.exponent >= 0) {
        return value;
    }

    var integer = signedMagnitude(analysis.negative, analysis.parts.significand);
    const residue = float_residue.classifyRightShiftResidue64(integer, -analysis.parts.exponent);
    integer = moveInteger(integer, analysis.parts.exponent);

    if (shouldIncrease(mode, residue, integer)) {
        integer +%= 1;
    }

    const result = if (integer == 0)
        float_format.Binary32.zero(analysis.negative)
    else
        try float_parts.roundFloat32Parts(
            float_parts.WideFloatParts{
                .negative = analysis.negative,
                .exponent = 0,
                .significand = unsignedMagnitude(integer),
            },
            control,
            .zero,
            status,
        );

    if (residue != .zero and exact) {
        try float_exception.processFloatException(.inexact, control, status);
    }

    return result;
}

fn roundParts64(
    value: u64,
    analysis: float_parts.FloatAnalysis,
    control: a64_state.FloatControl,
    mode: float_rounding.RoundingMode,
    exact: bool,
    status: *float_status.FloatStatus,
) float_exception.FloatExceptionError!u64 {
    switch (analysis.kind) {
        .quiet_nan, .signaling_nan => return try a64_float_nan.processNan64(control, value, status),
        .infinity => return float_format.Binary64.infinity(analysis.negative),
        .zero => return float_format.Binary64.zero(analysis.negative),
        .finite => {},
    }

    if (analysis.parts.exponent >= 0) {
        return value;
    }

    var integer = signedMagnitude(analysis.negative, analysis.parts.significand);
    const residue = float_residue.classifyRightShiftResidue64(integer, -analysis.parts.exponent);
    integer = moveInteger(integer, analysis.parts.exponent);

    if (shouldIncrease(mode, residue, integer)) {
        integer +%= 1;
    }

    const result = if (integer == 0)
        float_format.Binary64.zero(analysis.negative)
    else
        try float_parts.roundFloat64Parts(
            float_parts.WideFloatParts{
                .negative = analysis.negative,
                .exponent = 0,
                .significand = unsignedMagnitude(integer),
            },
            control,
            .zero,
            status,
        );

    if (residue != .zero and exact) {
        try float_exception.processFloatException(.inexact, control, status);
    }

    return result;
}

pub fn roundIntegral32(
    value: u32,
    control: a64_state.FloatControl,
    mode: float_rounding.RoundingMode,
    exact: bool,
    status: *float_status.FloatStatus,
) float_exception.FloatExceptionError!u32 {
    const analysis = try float_parts.splitFloat32(value, control, status);
    return roundParts32(value, analysis, control, mode, exact, status);
}

pub fn roundIntegral64(
    value: u64,
    control: a64_state.FloatControl,
    mode: float_rounding.RoundingMode,
    exact: bool,
    status: *float_status.FloatStatus,
) float_exception.FloatExceptionError!u64 {
    const analysis = try float_parts.splitFloat64(value, control, status);
    return roundParts64(value, analysis, control, mode, exact, status);
}
