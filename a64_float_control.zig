const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const float_exception = @import("float_exception.zig");
const float_format = @import("float_format.zig");
const float_parts = @import("float_parts.zig");
const float_status = @import("float_status.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;
const a64_nan = @import("a64_float_nan.zig");
const isDenormal32 = a64_nan.isDenormal32;
const isDenormal64 = a64_nan.isDenormal64;
const isNan32 = a64_nan.isNan32;
const isNan64 = a64_nan.isNan64;
const isSignalingNan16 = a64_nan.isSignalingNan16;
const isSignalingNan32 = a64_nan.isSignalingNan32;
const isSignalingNan64 = a64_nan.isSignalingNan64;

pub fn floatInput32(control: a64_state.FloatControl, value: u32) u32 {
    if (control.fz() and isDenormal32(value)) {
        return value & float_format.Binary32.sign_mask;
    }
    return value;
}

pub fn floatInput64(control: a64_state.FloatControl, value: u64) u64 {
    if (control.fz() and isDenormal64(value)) {
        return value & float_format.Binary64.sign_mask;
    }
    return value;
}

pub fn floatOutput32(control: a64_state.FloatControl, value: u32) u32 {
    if (control.fz() and isDenormal32(value)) {
        return 0;
    }
    if (control.dn() and isNan32(value)) {
        return 0x7fc00000;
    }
    return value;
}

pub fn floatOutput64(control: a64_state.FloatControl, value: u64) u64 {
    if (control.fz() and isDenormal64(value)) {
        return 0;
    }
    if (control.dn() and isNan64(value)) {
        return 0x7ff8000000000000;
    }
    return value;
}

pub fn effectiveFloatControl(control: a64_state.FloatControl, mode: FloatNanMode64) a64_state.FloatControl {
    return if (mode == .force_default) a64_state.FloatControl.init(control.raw() | 0x02000000) else control;
}

pub fn useAccurateNan(mode: FloatNanMode64) bool {
    return mode == .accurate;
}

pub fn finishFloat32(control: a64_state.FloatControl, mode: FloatNanMode64, value: u32) u32 {
    var result = floatOutput32(control, value);
    if (useAccurateNan(mode) and !control.dn() and isNan32(result)) {
        result ^= 0x80000000;
    }
    return result;
}

pub fn finishFloat64(control: a64_state.FloatControl, mode: FloatNanMode64, value: u64) u64 {
    var result = floatOutput64(control, value);
    if (useAccurateNan(mode) and !control.dn() and isNan64(result)) {
        result ^= 0x8000000000000000;
    }
    return result;
}

pub fn expandFloatConstant16(encoded: u8) u16 {
    const sign = @as(u16, encoded >> 7);
    const exponent_base = if (((encoded >> 6) & 1) != 0) @as(u16, 0x0c) else @as(u16, 0x10);
    const exponent = exponent_base | @as(u16, (encoded >> 4) & 3);
    const fraction = @as(u16, encoded & 0xf) << 6;
    return (sign << 15) | (exponent << 10) | fraction;
}

pub fn expandFloatConstant32(encoded: u8) u32 {
    const sign = @as(u32, encoded >> 7);
    const exponent_base = if (((encoded >> 6) & 1) != 0) @as(u32, 0x7c) else @as(u32, 0x80);
    const exponent = exponent_base | @as(u32, (encoded >> 4) & 3);
    const fraction = @as(u32, encoded & 0xf) << 19;
    return (sign << 31) | (exponent << 23) | fraction;
}

pub fn expandFloatConstant64(encoded: u8) u64 {
    const sign = @as(u64, encoded >> 7);
    const exponent_base = if (((encoded >> 6) & 1) != 0) @as(u64, 0x3fc) else @as(u64, 0x400);
    const exponent = exponent_base | @as(u64, (encoded >> 4) & 3);
    const fraction = @as(u64, encoded & 0xf) << 48;
    return (sign << 63) | (exponent << 52) | fraction;
}

pub fn float32To64(control: a64_state.FloatControl, value: u32) u64 {
    const input = @bitCast(f32, floatInput32(control, value));
    return floatOutput64(control, @bitCast(u64, @floatCast(f64, input)));
}

pub fn float64To32(control: a64_state.FloatControl, value: u64) u32 {
    const input = @bitCast(f64, floatInput64(control, value));
    return floatOutput32(control, @bitCast(u32, @floatCast(f32, input)));
}

fn convertedNan16To32(control: a64_state.FloatControl, value: u16, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u32 {
    if (control.dn()) {
        return float_format.Binary32.defaultNan();
    }
    if (isSignalingNan16(value)) {
        try float_exception.processFloatException(.invalid_operation, control, status);
    }
    const sign = if ((value & float_format.Binary16.sign_mask) != 0) float_format.Binary32.sign_mask else @as(u32, 0);
    const payload = @as(u32, value & 0x01ff) << 13;
    return sign | float_format.Binary32.exponent_mask | float_format.Binary32.fraction_top_bit | payload;
}

fn convertedNan16To64(control: a64_state.FloatControl, value: u16, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u64 {
    if (control.dn()) {
        return float_format.Binary64.defaultNan();
    }
    if (isSignalingNan16(value)) {
        try float_exception.processFloatException(.invalid_operation, control, status);
    }
    const sign = if ((value & float_format.Binary16.sign_mask) != 0) float_format.Binary64.sign_mask else @as(u64, 0);
    const payload = @as(u64, value & 0x01ff) << 42;
    return sign | float_format.Binary64.exponent_mask | float_format.Binary64.fraction_top_bit | payload;
}

fn convertedNan32To16(control: a64_state.FloatControl, value: u32, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u16 {
    const sign = if ((value & float_format.Binary32.sign_mask) != 0) float_format.Binary16.sign_mask else @as(u16, 0);
    if (control.ahp()) {
        if (isSignalingNan32(value)) {
            try float_exception.processFloatException(.invalid_operation, control, status);
        }
        return sign;
    }
    if (control.dn()) {
        return float_format.Binary16.defaultNan();
    }
    if (isSignalingNan32(value)) {
        try float_exception.processFloatException(.invalid_operation, control, status);
    }
    return sign | float_format.Binary16.exponent_mask | float_format.Binary16.fraction_top_bit | @intCast(u16, (value >> 13) & 0x01ff);
}

fn convertedNan64To16(control: a64_state.FloatControl, value: u64, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u16 {
    const sign = if ((value & float_format.Binary64.sign_mask) != 0) float_format.Binary16.sign_mask else @as(u16, 0);
    if (control.ahp()) {
        if (isSignalingNan64(value)) {
            try float_exception.processFloatException(.invalid_operation, control, status);
        }
        return sign;
    }
    if (control.dn()) {
        return float_format.Binary16.defaultNan();
    }
    if (isSignalingNan64(value)) {
        try float_exception.processFloatException(.invalid_operation, control, status);
    }
    return sign | float_format.Binary16.exponent_mask | float_format.Binary16.fraction_top_bit | @intCast(u16, (value >> 42) & 0x01ff);
}

pub fn float16To32(control: a64_state.FloatControl, value: u16, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u32 {
    const analysis = try float_parts.splitFloat16(value, control, status);
    return switch (analysis.kind) {
        .zero => float_format.Binary32.zero(analysis.negative),
        .infinity => float_format.Binary32.infinity(analysis.negative),
        .quiet_nan, .signaling_nan => try convertedNan16To32(control, value, status),
        .finite => try float_parts.roundFloat32(analysis.parts, control, status),
    };
}

pub fn float16To64(control: a64_state.FloatControl, value: u16, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u64 {
    const analysis = try float_parts.splitFloat16(value, control, status);
    return switch (analysis.kind) {
        .zero => float_format.Binary64.zero(analysis.negative),
        .infinity => float_format.Binary64.infinity(analysis.negative),
        .quiet_nan, .signaling_nan => try convertedNan16To64(control, value, status),
        .finite => try float_parts.roundFloat64(analysis.parts, control, status),
    };
}

pub fn float32To16(control: a64_state.FloatControl, value: u32, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u16 {
    const analysis = try float_parts.splitFloat32(value, control, status);
    return switch (analysis.kind) {
        .zero => float_format.Binary16.zero(analysis.negative),
        .infinity => if (control.ahp()) blk: {
            try float_exception.processFloatException(.invalid_operation, control, status);
            break :blk float_format.Binary16.zero(analysis.negative) | 0x7fff;
        } else float_format.Binary16.infinity(analysis.negative),
        .quiet_nan, .signaling_nan => try convertedNan32To16(control, value, status),
        .finite => try float_parts.roundFloat16(analysis.parts, control, status),
    };
}

pub fn float64To16(control: a64_state.FloatControl, value: u64, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u16 {
    const analysis = try float_parts.splitFloat64(value, control, status);
    return switch (analysis.kind) {
        .zero => float_format.Binary16.zero(analysis.negative),
        .infinity => if (control.ahp()) blk: {
            try float_exception.processFloatException(.invalid_operation, control, status);
            break :blk float_format.Binary16.zero(analysis.negative) | 0x7fff;
        } else float_format.Binary16.infinity(analysis.negative),
        .quiet_nan, .signaling_nan => try convertedNan64To16(control, value, status),
        .finite => try float_parts.roundFloat16(analysis.parts, control, status),
    };
}

pub fn float64To32Odd(control: a64_state.FloatControl, value: u64) u32 {
    const input = floatInput64(control, value);
    const sign = if ((input & float_format.Binary64.sign_mask) != 0) float_format.Binary32.sign_mask else @as(u32, 0);
    const exponent_raw = (input & float_format.Binary64.exponent_mask) >> @intCast(u6, float_format.Binary64.stored_fraction_bits);
    const fraction = input & float_format.Binary64.fraction_mask;
    if (exponent_raw == 0 and fraction == 0) {
        return sign;
    }
    if (exponent_raw == (@as(u64, 1) << @intCast(u6, float_format.Binary64.exponent_bits)) - 1) {
        return float64To32(control, value);
    }

    const exponent = if (exponent_raw == 0) float_format.Binary64.exponent_min else @intCast(i32, exponent_raw) - @intCast(i32, float_format.Binary64.exponent_bias);
    const mantissa = if (exponent_raw == 0) fraction else float_format.Binary64.hidden_bit | fraction;
    if (exponent > float_format.Binary32.exponent_max) {
        return sign | (float_format.Binary32.exponent_mask - 1);
    }
    if (control.fz() and exponent < float_format.Binary32.exponent_min) {
        return sign;
    }

    var result: u32 = sign;
    var discarded = false;
    if (exponent >= float_format.Binary32.exponent_min) {
        const dropped = mantissa & ((@as(u64, 1) << 29) - 1);
        const kept = @intCast(u32, mantissa >> 29);
        result |= @intCast(u32, exponent + @intCast(i32, float_format.Binary32.exponent_bias)) << @intCast(u5, float_format.Binary32.stored_fraction_bits);
        result |= kept & float_format.Binary32.fraction_mask;
        discarded = dropped != 0;
    } else {
        const scale = exponent + 97;
        const kept = if (scale >= 0) mantissa << @intCast(u6, scale) else if (-scale >= 64) @as(u64, 0) else mantissa >> @intCast(u6, -scale);
        const dropped = if (scale >= 0) @as(u64, 0) else if (-scale >= 64) mantissa else mantissa & ((@as(u64, 1) << @intCast(u6, -scale)) - 1);
        result |= @intCast(u32, kept) & float_format.Binary32.fraction_mask;
        discarded = dropped != 0;
    }
    if (discarded) {
        result |= 1;
    }
    return floatOutput32(control, result);
}

fn applyFraction32(value: u32, fractional_bits: usize) u32 {
    if (fractional_bits == 0 or value == 0) {
        return value;
    }
    const exponent = @intCast(u32, 127 - @intCast(i32, fractional_bits));
    return @bitCast(u32, @bitCast(f32, value) * @bitCast(f32, exponent << 23));
}

fn applyFraction64(value: u64, fractional_bits: usize) u64 {
    if (fractional_bits == 0 or value == 0) {
        return value;
    }
    const exponent = @intCast(u64, 1023 - @intCast(i32, fractional_bits));
    return @bitCast(u64, @bitCast(f64, value) * @bitCast(f64, exponent << 52));
}

pub fn signedWordToFloat32(value: u32, fractional_bits: usize) u32 {
    return applyFraction32(@bitCast(u32, @intToFloat(f32, @bitCast(i32, value))), fractional_bits);
}

pub fn unsignedWordToFloat32(value: u32, fractional_bits: usize) u32 {
    return applyFraction32(@bitCast(u32, @intToFloat(f32, value)), fractional_bits);
}

fn roundedUnsignedDoublewordToFloat32(control: a64_state.FloatControl, value: u64, negative: bool, fractional_bits: usize) u32 {
    if (value == 0) {
        return 0;
    }
    if (value < (@as(u64, 1) << 24)) {
        return applyFraction32(@bitCast(u32, @intToFloat(f32, value)), fractional_bits);
    }

    var exponent = @intCast(u8, 63 - @clz(value));
    const shift = @intCast(u6, exponent - 23);
    const remainder_mask = (@as(u64, 1) << shift) - 1;
    const remainder = value & remainder_mask;
    var significand = value >> shift;
    const increment = switch (control.rounding()) {
        .nearest => blk: {
            const half = @as(u64, 1) << @intCast(u6, shift - 1);
            break :blk remainder > half or (remainder == half and (significand & 1) != 0);
        },
        .positive => !negative and remainder != 0,
        .negative => negative and remainder != 0,
        .nearest_away => remainder >= (@as(u64, 1) << @intCast(u6, shift - 1)),
        .zero => false,
    };
    if (increment) {
        significand += 1;
        if (significand == (@as(u64, 1) << 24)) {
            significand >>= 1;
            exponent += 1;
        }
    }
    return applyFraction32((@as(u32, exponent) + 127) << 23 | @intCast(u32, significand & ((@as(u64, 1) << 23) - 1)), fractional_bits);
}

pub fn signedDoublewordToFloat32(control: a64_state.FloatControl, value: u64, fractional_bits: usize) u32 {
    const negative = @bitCast(i64, value) < 0;
    const magnitude = if (negative) ~value +% 1 else value;
    const converted = roundedUnsignedDoublewordToFloat32(control, magnitude, negative, fractional_bits);
    return converted | (if (negative) @as(u32, 0x80000000) else 0);
}

pub fn unsignedDoublewordToFloat32(control: a64_state.FloatControl, value: u64, fractional_bits: usize) u32 {
    return roundedUnsignedDoublewordToFloat32(control, value, false, fractional_bits);
}

pub fn signedWordToFloat64(value: u32, fractional_bits: usize) u64 {
    return applyFraction64(@bitCast(u64, @intToFloat(f64, @bitCast(i32, value))), fractional_bits);
}

pub fn signedDoublewordToFloat64(value: u64, fractional_bits: usize) u64 {
    return applyFraction64(@bitCast(u64, @intToFloat(f64, @bitCast(i64, value))), fractional_bits);
}

pub fn unsignedDoublewordToFloat64(control: a64_state.FloatControl, value: u64, fractional_bits: usize) u64 {
    if (value < (@as(u64, 1) << 53)) {
        return applyFraction64(@bitCast(u64, @intToFloat(f64, value)), fractional_bits);
    }

    var exponent = @intCast(u11, 63 - @clz(value));
    const shift = @intCast(u6, exponent - 52);
    const remainder_mask = (@as(u64, 1) << shift) - 1;
    const remainder = value & remainder_mask;
    var significand = value >> shift;
    const increment = switch (control.rounding()) {
        .nearest => blk: {
            const half = @as(u64, 1) << @intCast(u6, shift - 1);
            break :blk remainder > half or (remainder == half and (significand & 1) != 0);
        },
        .positive => remainder != 0,
        .negative, .zero => false,
        .nearest_away => remainder >= (@as(u64, 1) << @intCast(u6, shift - 1)),
    };
    if (increment) {
        significand += 1;
        if (significand == (@as(u64, 1) << 53)) {
            significand >>= 1;
            exponent += 1;
        }
    }
    return applyFraction64(((@as(u64, exponent) + 1023) << 52) | (significand & ((@as(u64, 1) << 52) - 1)), fractional_bits);
}

pub fn unsignedWordToFloat64(value: u32, fractional_bits: usize) u64 {
    return applyFraction64(@bitCast(u64, @intToFloat(f64, value)), fractional_bits);
}

pub fn floatToSignedWord(control: a64_state.FloatControl, double: bool, value: u64) u32 {
    const number = if (double)
        @bitCast(f64, floatInput64(control, value))
    else
        @as(f64, @bitCast(f32, floatInput32(control, @intCast(u32, value))));
    if (number != number) {
        return 0;
    }
    if (number <= @as(f64, -2147483648.0)) {
        return 0x80000000;
    }
    if (number >= @as(f64, 2147483647.0)) {
        return 0x7fffffff;
    }
    return @bitCast(u32, @floatToInt(i32, number));
}

pub fn floatToUnsignedWord(control: a64_state.FloatControl, double: bool, value: u64) u32 {
    const number = if (double)
        @bitCast(f64, floatInput64(control, value))
    else
        @as(f64, @bitCast(f32, floatInput32(control, @intCast(u32, value))));
    if (number != number or number <= @as(f64, 0.0)) {
        return 0;
    }
    if (number >= @as(f64, 4294967295.0)) {
        return 0xffffffff;
    }
    return @floatToInt(u32, number);
}
