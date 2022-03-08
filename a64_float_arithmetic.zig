const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub fn floatAdd(base_control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, left: u64, right: u64) u64 {
    const control = effectiveFloatControl(base_control, mode);
    if (double) {
        const left_input = floatInput64(control, left);
        const right_input = floatInput64(control, right);
        if (chooseBinaryNan64(control, mode, left_input, right_input)) |nan| {
            return nan;
        }
        return finishFloat64(control, mode, @bitCast(u64, @bitCast(f64, left_input) + @bitCast(f64, right_input)));
    }
    const left_input = floatInput32(control, @intCast(u32, left));
    const right_input = floatInput32(control, @intCast(u32, right));
    if (chooseBinaryNan32(control, mode, left_input, right_input)) |nan| {
        return @as(u64, nan);
    }
    const result = @bitCast(u32, @bitCast(f32, left_input) + @bitCast(f32, right_input));
    return @as(u64, finishFloat32(control, mode, result));
}

pub fn floatDiv(base_control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, left: u64, right: u64) u64 {
    const control = effectiveFloatControl(base_control, mode);
    if (double) {
        const left_input = floatInput64(control, left);
        const right_input = floatInput64(control, right);
        if (chooseBinaryNan64(control, mode, left_input, right_input)) |nan| {
            return nan;
        }
        return finishFloat64(control, mode, @bitCast(u64, @bitCast(f64, left_input) / @bitCast(f64, right_input)));
    }
    const left_input = floatInput32(control, @intCast(u32, left));
    const right_input = floatInput32(control, @intCast(u32, right));
    if (chooseBinaryNan32(control, mode, left_input, right_input)) |nan| {
        return @as(u64, nan);
    }
    const result = @bitCast(u32, @bitCast(f32, left_input) / @bitCast(f32, right_input));
    return @as(u64, finishFloat32(control, mode, result));
}

pub fn floatMul(base_control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, left: u64, right: u64) u64 {
    const control = effectiveFloatControl(base_control, mode);
    if (double) {
        const left_input = floatInput64(control, left);
        const right_input = floatInput64(control, right);
        if (chooseBinaryNan64(control, mode, left_input, right_input)) |nan| {
            return nan;
        }
        return finishFloat64(control, mode, @bitCast(u64, @bitCast(f64, left_input) * @bitCast(f64, right_input)));
    }
    const left_input = floatInput32(control, @intCast(u32, left));
    const right_input = floatInput32(control, @intCast(u32, right));
    if (chooseBinaryNan32(control, mode, left_input, right_input)) |nan| {
        return @as(u64, nan);
    }
    const result = @bitCast(u32, @bitCast(f32, left_input) * @bitCast(f32, right_input));
    return @as(u64, finishFloat32(control, mode, result));
}

pub fn floatSub(base_control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, left: u64, right: u64) u64 {
    const control = effectiveFloatControl(base_control, mode);
    if (double) {
        const left_input = floatInput64(control, left);
        const right_input = floatInput64(control, right);
        if (chooseBinaryNan64(control, mode, left_input, right_input)) |nan| {
            return nan;
        }
        return finishFloat64(control, mode, @bitCast(u64, @bitCast(f64, left_input) - @bitCast(f64, right_input)));
    }
    const left_input = floatInput32(control, @intCast(u32, left));
    const right_input = floatInput32(control, @intCast(u32, right));
    if (chooseBinaryNan32(control, mode, left_input, right_input)) |nan| {
        return @as(u64, nan);
    }
    const result = @bitCast(u32, @bitCast(f32, left_input) - @bitCast(f32, right_input));
    return @as(u64, finishFloat32(control, mode, result));
}

pub fn floatSqrt(base_control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, value: u64) u64 {
    const control = effectiveFloatControl(base_control, mode);
    if (double) {
        const input = floatInput64(control, value);
        if (chooseUnaryNan64(control, mode, input)) |nan| {
            return nan;
        }
        return finishFloat64(control, mode, @bitCast(u64, @sqrt(@bitCast(f64, input))));
    }
    const input = floatInput32(control, @intCast(u32, value));
    if (chooseUnaryNan32(control, mode, input)) |nan| {
        return @as(u64, nan);
    }
    return @as(u64, finishFloat32(control, mode, @bitCast(u32, @sqrt(@bitCast(f32, input)))));
}

