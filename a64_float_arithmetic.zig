const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const float_fused = @import("float_fused.zig");
const float_format = @import("float_format.zig");
const float_status = @import("float_status.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

fn isZero32(value: u32) bool {
    return (value & ~float_format.Binary32.sign_mask) == 0;
}

fn isZero64(value: u64) bool {
    return (value & ~float_format.Binary64.sign_mask) == 0;
}

fn isInfinity32(value: u32) bool {
    return (value & ~float_format.Binary32.sign_mask) == float_format.Binary32.infinity(false);
}

fn isInfinity64(value: u64) bool {
    return (value & ~float_format.Binary64.sign_mask) == float_format.Binary64.infinity(false);
}

fn invalidFusedNan32(addend: u32, left: u32, right: u32) bool {
    return isQuietNan32(addend) and ((isInfinity32(left) and isZero32(right)) or (isZero32(left) and isInfinity32(right)));
}

fn invalidFusedNan64(addend: u64, left: u64, right: u64) bool {
    return isQuietNan64(addend) and ((isInfinity64(left) and isZero64(right)) or (isZero64(left) and isInfinity64(right)));
}

fn invalidExtendedProduct32(left: u32, right: u32) bool {
    return (isInfinity32(left) and isZero32(right)) or (isZero32(left) and isInfinity32(right));
}

fn invalidExtendedProduct64(left: u64, right: u64) bool {
    return (isInfinity64(left) and isZero64(right)) or (isZero64(left) and isInfinity64(right));
}

fn extendedProduct32(left: u32, right: u32) u32 {
    return (left ^ right) & float_format.Binary32.sign_mask | float_format.Binary32.finite(false, 0, 2);
}

fn extendedProduct64(left: u64, right: u64) u64 {
    return (left ^ right) & float_format.Binary64.sign_mask | float_format.Binary64.finite(false, 0, 2);
}

fn needsPreciseFused32(control: a64_state.FloatControl, value: u32) bool {
    return control.fz() and (value & ~float_format.Binary32.sign_mask) == float_format.Binary32.hidden_bit;
}

fn needsPreciseFused64(control: a64_state.FloatControl, value: u64) bool {
    return control.fz() and (value & ~float_format.Binary64.sign_mask) == float_format.Binary64.hidden_bit;
}

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

pub fn floatMulExtended(base_control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, left: u64, right: u64) u64 {
    const control = effectiveFloatControl(base_control, mode);
    if (double) {
        const left_input = floatInput64(control, left);
        const right_input = floatInput64(control, right);
        if (chooseBinaryNan64(control, mode, left_input, right_input)) |nan| {
            return nan;
        }
        if (invalidExtendedProduct64(left_input, right_input)) {
            return extendedProduct64(left_input, right_input);
        }
        return finishFloat64(control, mode, @bitCast(u64, @bitCast(f64, left_input) * @bitCast(f64, right_input)));
    }
    const left_input = floatInput32(control, @intCast(u32, left));
    const right_input = floatInput32(control, @intCast(u32, right));
    if (chooseBinaryNan32(control, mode, left_input, right_input)) |nan| {
        return @as(u64, nan);
    }
    if (invalidExtendedProduct32(left_input, right_input)) {
        return @as(u64, extendedProduct32(left_input, right_input));
    }
    const result = @bitCast(u32, @bitCast(f32, left_input) * @bitCast(f32, right_input));
    return @as(u64, finishFloat32(control, mode, result));
}

pub fn floatMulAdd(base_control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, addend: u64, left: u64, right: u64) u64 {
    const control = effectiveFloatControl(base_control, mode);
    if (double) {
        const addend_input = floatInput64(control, addend);
        const left_input = floatInput64(control, left);
        const right_input = floatInput64(control, right);
        if (invalidFusedNan64(addend_input, left_input, right_input)) {
            return float_format.Binary64.defaultNan();
        }
        if (chooseTernaryNan64(control, mode, addend_input, left_input, right_input)) |nan| {
            return nan;
        }
        const result = @bitCast(u64, @mulAdd(f64, @bitCast(f64, left_input), @bitCast(f64, right_input), @bitCast(f64, addend_input)));
        if (needsPreciseFused64(control, result)) {
            var status = float_status.FloatStatus.init(0);
            if (float_fused.mulAdd64(addend_input, left_input, right_input, control, &status)) |precise| {
                return finishFloat64(control, mode, precise);
            } else |_| {}
        }
        return finishFloat64(control, mode, result);
    }
    const addend_input = floatInput32(control, @intCast(u32, addend));
    const left_input = floatInput32(control, @intCast(u32, left));
    const right_input = floatInput32(control, @intCast(u32, right));
    if (invalidFusedNan32(addend_input, left_input, right_input)) {
        return @as(u64, float_format.Binary32.defaultNan());
    }
    if (chooseTernaryNan32(control, mode, addend_input, left_input, right_input)) |nan| {
        return @as(u64, nan);
    }
    const result = @bitCast(u32, @mulAdd(f32, @bitCast(f32, left_input), @bitCast(f32, right_input), @bitCast(f32, addend_input)));
    if (needsPreciseFused32(control, result)) {
        var status = float_status.FloatStatus.init(0);
        if (float_fused.mulAdd32(addend_input, left_input, right_input, control, &status)) |precise| {
            return @as(u64, finishFloat32(control, mode, precise));
        } else |_| {}
    }
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
