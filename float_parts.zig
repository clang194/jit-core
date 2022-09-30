const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const float_exception = @import("float_exception.zig");
const float_format = @import("float_format.zig");
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

fn emptyParts(negative: bool) WideFloatParts {
    return WideFloatParts{
        .negative = negative,
        .exponent = 0,
        .significand = 0,
    };
}

pub fn splitFloat32(value: u32, control: a64_state.FloatControl, status: *float_status.FloatStatus) float_exception.FloatExceptionError!FloatAnalysis {
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

pub fn splitFloat64(value: u64, control: a64_state.FloatControl, status: *float_status.FloatStatus) float_exception.FloatExceptionError!FloatAnalysis {
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
