const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;
const a64_control = @import("a64_float_control.zig");
const effectiveFloatControl = a64_control.effectiveFloatControl;
const finishFloat32 = a64_control.finishFloat32;
const finishFloat64 = a64_control.finishFloat64;
const floatInput32 = a64_control.floatInput32;
const floatInput64 = a64_control.floatInput64;
const useAccurateNan = a64_control.useAccurateNan;
const a64_nan = @import("a64_float_nan.zig");
const chooseBinaryNan32 = a64_nan.chooseBinaryNan32;
const chooseBinaryNan64 = a64_nan.chooseBinaryNan64;
const isNan32 = a64_nan.isNan32;
const isNan64 = a64_nan.isNan64;
const isSignalingNan32 = a64_nan.isSignalingNan32;
const isSignalingNan64 = a64_nan.isSignalingNan64;

pub fn floatMax(base_control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, left: u64, right: u64) u64 {
    const control = effectiveFloatControl(base_control, mode);
    if (double) {
        const left_input = floatInput64(control, left);
        const right_input = floatInput64(control, right);
        if (chooseBinaryNan64(control, mode, left_input, right_input)) |nan| {
            return nan;
        }
        if (isNan64(left_input) or isNan64(right_input)) {
            const selected = if (mode == .unchecked and !control.dn()) right_input else if (isNan64(left_input)) left_input else right_input;
            return finishFloat64(control, mode, selected);
        }
        const left_value = @bitCast(f64, left_input);
        const right_value = @bitCast(f64, right_input);
        const selected = if (left_value == right_value and (left_input & 0x7fffffffffffffff) == 0 and (right_input & 0x7fffffffffffffff) == 0)
            left_input & right_input
        else if (left_value > right_value)
            left_input
        else
            right_input;
        return finishFloat64(control, mode, selected);
    }
    const left_input = floatInput32(control, @intCast(u32, left));
    const right_input = floatInput32(control, @intCast(u32, right));
    if (chooseBinaryNan32(control, mode, left_input, right_input)) |nan| {
        return @as(u64, nan);
    }
    if (isNan32(left_input) or isNan32(right_input)) {
        const selected = if (mode == .unchecked and !control.dn()) right_input else if (isNan32(left_input)) left_input else right_input;
        return @as(u64, finishFloat32(control, mode, selected));
    }
    const left_value = @bitCast(f32, left_input);
    const right_value = @bitCast(f32, right_input);
    const selected = if (left_value == right_value and (left_input & 0x7fffffff) == 0 and (right_input & 0x7fffffff) == 0)
        left_input & right_input
    else if (left_value > right_value)
        left_input
    else
        right_input;
    return @as(u64, finishFloat32(control, mode, selected));
}

pub fn floatMaxNumber(base_control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, left: u64, right: u64) u64 {
    const control = effectiveFloatControl(base_control, mode);
    if (double) {
        const left_input = floatInput64(control, left);
        const right_input = floatInput64(control, right);
        const left_nan = isNan64(left_input);
        const right_nan = isNan64(right_input);
        if (useAccurateNan(mode) and !control.dn()) {
            if (isSignalingNan64(left_input)) {
                return left_input | 0x0008000000000000;
            }
            if (isSignalingNan64(right_input)) {
                return right_input | 0x0008000000000000;
            }
        }
        if (left_nan or right_nan) {
            if (!left_nan) {
                return finishFloat64(control, mode, left_input);
            }
            if (!right_nan) {
                return finishFloat64(control, mode, right_input);
            }
            return finishFloat64(control, mode, left_input);
        }
        const left_value = @bitCast(f64, left_input);
        const right_value = @bitCast(f64, right_input);
        const selected = if (left_value == right_value and (left_input & 0x7fffffffffffffff) == 0 and (right_input & 0x7fffffffffffffff) == 0)
            left_input & right_input
        else if (left_value > right_value)
            left_input
        else
            right_input;
        return finishFloat64(control, mode, selected);
    }
    const left_input = floatInput32(control, @intCast(u32, left));
    const right_input = floatInput32(control, @intCast(u32, right));
    const left_nan = isNan32(left_input);
    const right_nan = isNan32(right_input);
    if (useAccurateNan(mode) and !control.dn()) {
        if (isSignalingNan32(left_input)) {
            return @as(u64, left_input | 0x00400000);
        }
        if (isSignalingNan32(right_input)) {
            return @as(u64, right_input | 0x00400000);
        }
    }
    if (left_nan or right_nan) {
        if (!left_nan) {
            return @as(u64, finishFloat32(control, mode, left_input));
        }
        if (!right_nan) {
            return @as(u64, finishFloat32(control, mode, right_input));
        }
        return @as(u64, finishFloat32(control, mode, left_input));
    }
    const left_value = @bitCast(f32, left_input);
    const right_value = @bitCast(f32, right_input);
    const selected = if (left_value == right_value and (left_input & 0x7fffffff) == 0 and (right_input & 0x7fffffff) == 0)
        left_input & right_input
    else if (left_value > right_value)
        left_input
    else
        right_input;
    return @as(u64, finishFloat32(control, mode, selected));
}

pub fn floatMinNumber(base_control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, left: u64, right: u64) u64 {
    const control = effectiveFloatControl(base_control, mode);
    if (double) {
        const left_input = floatInput64(control, left);
        const right_input = floatInput64(control, right);
        const left_nan = isNan64(left_input);
        const right_nan = isNan64(right_input);
        if (useAccurateNan(mode) and !control.dn()) {
            if (isSignalingNan64(left_input)) {
                return left_input | 0x0008000000000000;
            }
            if (isSignalingNan64(right_input)) {
                return right_input | 0x0008000000000000;
            }
        }
        if (left_nan or right_nan) {
            if (!left_nan) {
                return finishFloat64(control, mode, left_input);
            }
            if (!right_nan) {
                return finishFloat64(control, mode, right_input);
            }
            return finishFloat64(control, mode, left_input);
        }
        const left_value = @bitCast(f64, left_input);
        const right_value = @bitCast(f64, right_input);
        const selected = if (left_value == right_value and (left_input & 0x7fffffffffffffff) == 0 and (right_input & 0x7fffffffffffffff) == 0)
            left_input | right_input
        else if (left_value < right_value)
            left_input
        else
            right_input;
        return finishFloat64(control, mode, selected);
    }
    const left_input = floatInput32(control, @intCast(u32, left));
    const right_input = floatInput32(control, @intCast(u32, right));
    const left_nan = isNan32(left_input);
    const right_nan = isNan32(right_input);
    if (useAccurateNan(mode) and !control.dn()) {
        if (isSignalingNan32(left_input)) {
            return @as(u64, left_input | 0x00400000);
        }
        if (isSignalingNan32(right_input)) {
            return @as(u64, right_input | 0x00400000);
        }
    }
    if (left_nan or right_nan) {
        if (!left_nan) {
            return @as(u64, finishFloat32(control, mode, left_input));
        }
        if (!right_nan) {
            return @as(u64, finishFloat32(control, mode, right_input));
        }
        return @as(u64, finishFloat32(control, mode, left_input));
    }
    const left_value = @bitCast(f32, left_input);
    const right_value = @bitCast(f32, right_input);
    const selected = if (left_value == right_value and (left_input & 0x7fffffff) == 0 and (right_input & 0x7fffffff) == 0)
        left_input | right_input
    else if (left_value < right_value)
        left_input
    else
        right_input;
    return @as(u64, finishFloat32(control, mode, selected));
}

pub fn floatMin(base_control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, left: u64, right: u64) u64 {
    const control = effectiveFloatControl(base_control, mode);
    if (double) {
        const left_input = floatInput64(control, left);
        const right_input = floatInput64(control, right);
        if (chooseBinaryNan64(control, mode, left_input, right_input)) |nan| {
            return nan;
        }
        if (isNan64(left_input) or isNan64(right_input)) {
            const selected = if (mode == .unchecked and !control.dn()) right_input else if (isNan64(left_input)) left_input else right_input;
            return finishFloat64(control, mode, selected);
        }
        const left_value = @bitCast(f64, left_input);
        const right_value = @bitCast(f64, right_input);
        const selected = if (left_value == right_value and (left_input & 0x7fffffffffffffff) == 0 and (right_input & 0x7fffffffffffffff) == 0)
            left_input | right_input
        else if (left_value < right_value)
            left_input
        else
            right_input;
        return finishFloat64(control, mode, selected);
    }
    const left_input = floatInput32(control, @intCast(u32, left));
    const right_input = floatInput32(control, @intCast(u32, right));
    if (chooseBinaryNan32(control, mode, left_input, right_input)) |nan| {
        return @as(u64, nan);
    }
    if (isNan32(left_input) or isNan32(right_input)) {
        const selected = if (mode == .unchecked and !control.dn()) right_input else if (isNan32(left_input)) left_input else right_input;
        return @as(u64, finishFloat32(control, mode, selected));
    }
    const left_value = @bitCast(f32, left_input);
    const right_value = @bitCast(f32, right_input);
    const selected = if (left_value == right_value and (left_input & 0x7fffffff) == 0 and (right_input & 0x7fffffff) == 0)
        left_input | right_input
    else if (left_value < right_value)
        left_input
    else
        right_input;
    return @as(u64, finishFloat32(control, mode, selected));
}

pub fn negateFloat(double: bool, value: u64) u64 {
    if (double) {
        return value ^ 0x8000000000000000;
    }
    return @as(u64, @intCast(u32, value) ^ 0x80000000);
}

pub fn compareFloat(control: a64_state.FloatControl, double: bool, left: u64, right: u64) u32 {
    if (double) {
        const left_word = floatInput64(control, left);
        const right_word = floatInput64(control, right);
        if (isNan64(left_word) or isNan64(right_word)) {
            return 0x30000000;
        }
        const left_value = @bitCast(f64, left_word);
        const right_value = @bitCast(f64, right_word);
        if (left_value == right_value) {
            return 0x60000000;
        }
        if (left_value < right_value) {
            return 0x80000000;
        }
        return 0x20000000;
    }

    const left_word = floatInput32(control, @intCast(u32, left));
    const right_word = floatInput32(control, @intCast(u32, right));
    if (isNan32(left_word) or isNan32(right_word)) {
        return 0x30000000;
    }
    const left_value = @bitCast(f32, left_word);
    const right_value = @bitCast(f32, right_word);
    if (left_value == right_value) {
        return 0x60000000;
    }
    if (left_value < right_value) {
        return 0x80000000;
    }
    return 0x20000000;
}
