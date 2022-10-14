const a64_float_nan = @import("a64_float_nan.zig");
const bits = @import("bits.zig");
const float_control = @import("float_control.zig");
const float_exception = @import("float_exception.zig");
const float_format = @import("float_format.zig");
const float_parts = @import("float_parts.zig");
const float_status = @import("float_status.zig");

fn estimateByte(value: u64) u8 {
    var adjusted = value & 0x1ff;
    if (adjusted < 256) {
        adjusted = adjusted * 2 + 1;
    } else {
        adjusted = (adjusted | 1) * 2;
    }
    var guess: u64 = 512;
    while (adjusted * (guess + 1) * (guess + 1) < (@as(u64, 1) << 28)) {
        guess += 1;
    }
    return @intCast(u8, (guess + 1) / 2);
}

fn estimateBits(value: float_parts.WideFloatParts, comptime Result: type, comptime fraction_bits: u6, comptime bias: u64, comptime mask: u64) Result {
    const exponent = (-(value.exponent + 1)) >> 1;
    const even = (value.exponent & 1) == 0;
    const scaled = bits.shiftRight64(value.significand, float_parts.normalized_point - if (even) @as(i32, 7) else @as(i32, 8));
    const estimate = @as(u64, estimateByte(scaled));
    const stored_exponent = @intCast(u64, exponent + @intCast(i32, bias));
    const stored_mantissa = estimate << (fraction_bits - 8);
    return @intCast(Result, (stored_exponent << fraction_bits) | (stored_mantissa & mask));
}

pub fn inverseRootEstimate32(value: u32, control: float_control.Control, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u32 {
    const analysis = try float_parts.splitFloat32(value, control, status);
    switch (analysis.kind) {
        .quiet_nan, .signaling_nan => return try a64_float_nan.processNan32(control, value, status),
        .zero => {
            try float_exception.processFloatException(.divide_by_zero, control, status);
            return float_format.Binary32.infinity(analysis.negative);
        },
        .infinity => {
            if (analysis.negative) {
                try float_exception.processFloatException(.invalid_operation, control, status);
                return float_format.Binary32.defaultNan();
            }
            return float_format.Binary32.zero(false);
        },
        .finite => {
            if (analysis.negative) {
                try float_exception.processFloatException(.invalid_operation, control, status);
                return float_format.Binary32.defaultNan();
            }
            return estimateBits(
                analysis.parts,
                u32,
                @intCast(u6, float_format.Binary32.stored_fraction_bits),
                float_format.Binary32.exponent_bias,
                float_format.Binary32.fraction_mask,
            );
        },
    }
}

pub fn inverseRootEstimate64(value: u64, control: float_control.Control, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u64 {
    const analysis = try float_parts.splitFloat64(value, control, status);
    switch (analysis.kind) {
        .quiet_nan, .signaling_nan => return try a64_float_nan.processNan64(control, value, status),
        .zero => {
            try float_exception.processFloatException(.divide_by_zero, control, status);
            return float_format.Binary64.infinity(analysis.negative);
        },
        .infinity => {
            if (analysis.negative) {
                try float_exception.processFloatException(.invalid_operation, control, status);
                return float_format.Binary64.defaultNan();
            }
            return float_format.Binary64.zero(false);
        },
        .finite => {
            if (analysis.negative) {
                try float_exception.processFloatException(.invalid_operation, control, status);
                return float_format.Binary64.defaultNan();
            }
            return estimateBits(
                analysis.parts,
                u64,
                @intCast(u6, float_format.Binary64.stored_fraction_bits),
                float_format.Binary64.exponent_bias,
                float_format.Binary64.fraction_mask,
            );
        },
    }
}
