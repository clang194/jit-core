const bits = @import("bits.zig");
const float_control = @import("float_control.zig");
const float_exception = @import("float_exception.zig");
const float_format = @import("float_format.zig");
const float_residue = @import("float_residue.zig");
const float_rounding = @import("float_rounding.zig");
const float_status = @import("float_status.zig");

const infinity_exponent_marker: i32 = 1000000;

pub const FloatKind = enum {
    finite,
    zero,
    infinity,
    quiet_nan,
    signaling_nan,
};

pub const WideFloatParts = struct {
    negative: bool,
    exponent: i32,
    significand: u64,
};

pub const FloatAnalysis = struct {
    kind: FloatKind,
    negative: bool,
    parts: WideFloatParts,
};

const NormalizedParts = struct {
    negative: bool,
    exponent: i32,
    significand: u64,
    residue: float_residue.ShiftResidue,
};

fn emptyParts(negative: bool) WideFloatParts {
    return WideFloatParts{
        .negative = negative,
        .exponent = 0,
        .significand = 0,
    };
}

fn normalizeParts(value: WideFloatParts, comptime fraction_bits: u6, extra_shift: i32) NormalizedParts {
    const highest = @intCast(i32, 63 - @clz(u64, value.significand));
    const shift = highest - @intCast(i32, fraction_bits) + extra_shift;
    return NormalizedParts{
        .negative = value.negative,
        .exponent = value.exponent + highest,
        .significand = bits.shiftRight64(value.significand, shift),
        .residue = float_residue.classifyRightShiftResidue64(value.significand, shift),
    };
}

fn shouldRoundUp(mode: float_rounding.RoundingMode, negative: bool, significand: u64, residue: float_residue.ShiftResidue) bool {
    return switch (mode) {
        .nearest => residue == .above_half or (residue == .half and (significand & 1) != 0),
        .positive => residue != .zero and !negative,
        .negative => residue != .zero and negative,
        .nearest_away => residue == .above_half or residue == .half,
        .zero => false,
    };
}

fn roundParts(
    value: WideFloatParts,
    control: float_control.Control,
    mode: float_rounding.RoundingMode,
    status: *float_status.FloatStatus,
    comptime Result: type,
    comptime exponent_bits: u5,
    comptime fraction_bits: u6,
    comptime exponent_min: i32,
    comptime fraction_mask: u64,
    comptime infinity_value: fn (bool) Result,
    comptime max_normal_value: fn (bool) Result,
) float_exception.FloatExceptionError!Result {
    if (value.significand == 0) {
        return @intCast(Result, if (value.negative) @as(u64, 1) << (exponent_bits + fraction_bits) else 0);
    }

    var normal = normalizeParts(value, fraction_bits, 0);

    if (control.fz() and normal.exponent < exponent_min) {
        status.setUnderflow(true);
        return @intCast(Result, if (normal.negative) @as(u64, 1) << (exponent_bits + fraction_bits) else 0);
    }

    var biased_exponent = normal.exponent - exponent_min + 1;
    if (biased_exponent < 0) {
        biased_exponent = 0;
    }

    if (biased_exponent == 0) {
        const shift = exponent_min - normal.exponent;
        normal = normalizeParts(value, fraction_bits, shift);
    }

    if (biased_exponent == 0 and (normal.residue != .zero or control.ufe())) {
        try float_exception.processFloatException(.underflow, control, status);
    }

    const increment = shouldRoundUp(mode, normal.negative, normal.significand, normal.residue);
    const overflow_to_infinity = switch (mode) {
        .nearest => true,
        .positive => !normal.negative,
        .negative => normal.negative,
        .nearest_away => true,
        .zero => false,
    };

    if (increment) {
        if ((normal.significand & fraction_mask) == fraction_mask) {
            if (normal.significand == fraction_mask) {
                normal.significand += 1;
                biased_exponent += 1;
            } else {
                normal.significand = (normal.significand + 1) / 2;
                biased_exponent += 1;
            }
        } else {
            normal.significand += 1;
        }
    }

    const max_biased_exponent = (@as(i32, 1) << exponent_bits) - 1;
    if (biased_exponent >= max_biased_exponent) {
        try float_exception.processFloatException(.overflow, control, status);
        try float_exception.processFloatException(.inexact, control, status);
        return if (overflow_to_infinity) infinity_value(normal.negative) else max_normal_value(normal.negative);
    }

    var result = if (normal.negative) @as(u64, 1) else @as(u64, 0);
    result <<= exponent_bits;
    result += @intCast(u64, biased_exponent);
    result <<= fraction_bits;
    result |= normal.significand & fraction_mask;

    if (normal.residue != .zero) {
        try float_exception.processFloatException(.inexact, control, status);
    }

    return @intCast(Result, result);
}

pub fn splitFloat32(value: u32, control: float_control.Control, status: *float_status.FloatStatus) float_exception.FloatExceptionError!FloatAnalysis {
    const negative = bits.getBit32(value, 31);
    const exponent_raw = (value & float_format.Binary32.exponent_mask) >> float_format.Binary32.stored_fraction_bits;
    const fraction = value & float_format.Binary32.fraction_mask;

    if (exponent_raw == 0) {
        if (fraction == 0 or control.fz()) {
            if (fraction != 0) {
                try float_exception.processFloatException(.input_denormal, control, status);
            }
            return FloatAnalysis{
                .kind = .zero,
                .negative = negative,
                .parts = emptyParts(negative),
            };
        }

        return FloatAnalysis{
            .kind = .finite,
            .negative = negative,
            .parts = WideFloatParts{
                .negative = negative,
                .exponent = float_format.Binary32.exponent_min - @intCast(i32, float_format.Binary32.stored_fraction_bits),
                .significand = fraction,
            },
        };
    }

    if (exponent_raw == (@as(u32, 1) << float_format.Binary32.exponent_bits) - 1) {
        if (fraction == 0) {
            return FloatAnalysis{
                .kind = .infinity,
                .negative = negative,
                .parts = WideFloatParts{
                    .negative = negative,
                    .exponent = infinity_exponent_marker,
                    .significand = 1,
                },
            };
        }

        return FloatAnalysis{
            .kind = if (bits.getBit32(fraction, @intCast(u5, float_format.Binary32.stored_fraction_bits - 1))) .quiet_nan else .signaling_nan,
            .negative = negative,
            .parts = emptyParts(negative),
        };
    }

    return FloatAnalysis{
        .kind = .finite,
        .negative = negative,
        .parts = WideFloatParts{
            .negative = negative,
            .exponent = @intCast(i32, exponent_raw) - @intCast(i32, float_format.Binary32.exponent_bias) - @intCast(i32, float_format.Binary32.stored_fraction_bits),
            .significand = fraction | float_format.Binary32.hidden_bit,
        },
    };
}

pub fn splitFloat64(value: u64, control: float_control.Control, status: *float_status.FloatStatus) float_exception.FloatExceptionError!FloatAnalysis {
    const negative = bits.getBit64(value, 63);
    const exponent_raw = (value & float_format.Binary64.exponent_mask) >> float_format.Binary64.stored_fraction_bits;
    const fraction = value & float_format.Binary64.fraction_mask;

    if (exponent_raw == 0) {
        if (fraction == 0 or control.fz()) {
            if (fraction != 0) {
                try float_exception.processFloatException(.input_denormal, control, status);
            }
            return FloatAnalysis{
                .kind = .zero,
                .negative = negative,
                .parts = emptyParts(negative),
            };
        }

        return FloatAnalysis{
            .kind = .finite,
            .negative = negative,
            .parts = WideFloatParts{
                .negative = negative,
                .exponent = float_format.Binary64.exponent_min - @intCast(i32, float_format.Binary64.stored_fraction_bits),
                .significand = fraction,
            },
        };
    }

    if (exponent_raw == (@as(u64, 1) << float_format.Binary64.exponent_bits) - 1) {
        if (fraction == 0) {
            return FloatAnalysis{
                .kind = .infinity,
                .negative = negative,
                .parts = WideFloatParts{
                    .negative = negative,
                    .exponent = infinity_exponent_marker,
                    .significand = 1,
                },
            };
        }

        return FloatAnalysis{
            .kind = if (bits.getBit64(fraction, @intCast(u6, float_format.Binary64.stored_fraction_bits - 1))) .quiet_nan else .signaling_nan,
            .negative = negative,
            .parts = emptyParts(negative),
        };
    }

    return FloatAnalysis{
        .kind = .finite,
        .negative = negative,
        .parts = WideFloatParts{
            .negative = negative,
            .exponent = @intCast(i32, exponent_raw) - @intCast(i32, float_format.Binary64.exponent_bias) - @intCast(i32, float_format.Binary64.stored_fraction_bits),
            .significand = fraction | float_format.Binary64.hidden_bit,
        },
    };
}

pub fn roundFloat32Parts(value: WideFloatParts, control: float_control.Control, mode: float_rounding.RoundingMode, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u32 {
    return roundParts(
        value,
        control,
        mode,
        status,
        u32,
        float_format.Binary32.exponent_bits,
        float_format.Binary32.stored_fraction_bits,
        float_format.Binary32.exponent_min,
        float_format.Binary32.fraction_mask,
        float_format.Binary32.infinity,
        float_format.Binary32.maxNormal,
    );
}

pub fn roundFloat32(value: WideFloatParts, control: float_control.Control, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u32 {
    return roundFloat32Parts(value, control, control.rounding(), status);
}

pub fn roundFloat64Parts(value: WideFloatParts, control: float_control.Control, mode: float_rounding.RoundingMode, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u64 {
    return roundParts(
        value,
        control,
        mode,
        status,
        u64,
        float_format.Binary64.exponent_bits,
        float_format.Binary64.stored_fraction_bits,
        float_format.Binary64.exponent_min,
        float_format.Binary64.fraction_mask,
        float_format.Binary64.infinity,
        float_format.Binary64.maxNormal,
    );
}

pub fn roundFloat64(value: WideFloatParts, control: float_control.Control, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u64 {
    return roundFloat64Parts(value, control, control.rounding(), status);
}
