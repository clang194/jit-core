const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub fn floatInput32(control: a64_state.FloatControl, value: u32) u32 {
    if (control.fz() and isDenormal32(value)) {
        return 0;
    }
    return value;
}

pub fn floatInput64(control: a64_state.FloatControl, value: u64) u64 {
    if (control.fz() and isDenormal64(value)) {
        return 0;
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

pub fn signedWordToFloat32(value: u32) u32 {
    return @bitCast(u32, @intToFloat(f32, @bitCast(i32, value)));
}

pub fn unsignedWordToFloat32(value: u32) u32 {
    return @bitCast(u32, @intToFloat(f32, value));
}

pub fn signedWordToFloat64(value: u32) u64 {
    return @bitCast(u64, @intToFloat(f64, @bitCast(i32, value)));
}

pub fn signedDoublewordToFloat64(value: u64) u64 {
    return @bitCast(u64, @intToFloat(f64, @bitCast(i64, value)));
}

pub fn unsignedDoublewordToFloat64(control: a64_state.FloatControl, value: u64) u64 {
    if (value < (@as(u64, 1) << 53)) {
        return @bitCast(u64, @intToFloat(f64, value));
    }

    var exponent = @intCast(u11, 63 - @clz(u64, value));
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
    };
    if (increment) {
        significand += 1;
        if (significand == (@as(u64, 1) << 53)) {
            significand >>= 1;
            exponent += 1;
        }
    }
    return ((@as(u64, exponent) + 1023) << 52) | (significand & ((@as(u64, 1) << 52) - 1));
}

pub fn unsignedWordToFloat64(value: u32) u64 {
    return @bitCast(u64, @intToFloat(f64, value));
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
