const a64_float_nan = @import("a64_float_nan.zig");
const float_control = @import("float_control.zig");
const float_exception = @import("float_exception.zig");
const float_format = @import("float_format.zig");
const float_parts = @import("float_parts.zig");
const float_status = @import("float_status.zig");

const target_point: i32 = 62;

fn highBit64(value: u64) i32 {
    return @intCast(i32, 63 - @clz(u64, value));
}

fn bit128(value: u128, comptime index: usize) bool {
    if (index >= 128) {
        @compileError("invalid bit index");
    }
    return ((value >> @intCast(u7, index)) & 1) != 0;
}

fn stickyRight(value: u128, amount: i32) u128 {
    if (amount < 0) {
        return shiftLeft(value, -amount);
    }
    if (amount == 0) {
        return value;
    }
    if (amount >= 128) {
        return if (value == 0) 0 else 1;
    }
    const shift = @intCast(u7, amount);
    const shifted = value >> shift;
    const lost = value & ((@as(u128, 1) << shift) - 1);
    return shifted | if (lost == 0) @as(u128, 0) else @as(u128, 1);
}

fn shiftLeft(value: u128, amount: i32) u128 {
    if (amount <= 0) {
        return value;
    }
    if (amount >= 128) {
        return 0;
    }
    return value << @intCast(u7, amount);
}

fn packWide(sign: bool, exponent: i32, value: u128) float_parts.WideFloatParts {
    const lower = @truncate(u64, value);
    return float_parts.WideFloatParts{
        .negative = sign,
        .exponent = exponent + 64,
        .significand = @truncate(u64, value >> 64) | if (lower == 0) @as(u64, 0) else @as(u64, 1),
    };
}

fn normalize(value: float_parts.WideFloatParts) float_parts.WideFloatParts {
    const offset = target_point - highBit64(value.significand);
    return float_parts.WideFloatParts{
        .negative = value.negative,
        .exponent = value.exponent - offset,
        .significand = value.significand << @intCast(u6, offset),
    };
}

fn fusedParts(addend_input: float_parts.WideFloatParts, left_input: float_parts.WideFloatParts, right_input: float_parts.WideFloatParts) float_parts.WideFloatParts {
    if (left_input.significand == 0 or right_input.significand == 0) {
        return addend_input;
    }

    const left = normalize(left_input);
    const right = normalize(right_input);
    const product_negative = left.negative != right.negative;
    var product_exponent = left.exponent + right.exponent;
    var product = @as(u128, left.significand) * @as(u128, right.significand);

    if (bit128(product, 125)) {
        product >>= 1;
        product_exponent += 1;
    }

    if (product == 0) {
        return addend_input;
    }
    if (addend_input.significand == 0) {
        return packWide(product_negative, product_exponent, product);
    }

    const addend = normalize(addend_input);
    const exponent_gap = product_exponent - (addend.exponent - target_point);
    if (product_negative == addend.negative) {
        if (exponent_gap <= 0) {
            return float_parts.WideFloatParts{
                .negative = addend.negative,
                .exponent = addend.exponent,
                .significand = addend.significand + @truncate(u64, stickyRight(product, target_point - exponent_gap)),
            };
        }
        const result = product + stickyRight(@as(u128, addend.significand), exponent_gap - target_point);
        return packWide(product_negative, product_exponent, result);
    }

    const addend_wide = @as(u128, addend.significand) << @intCast(u7, target_point);
    var result_negative: bool = undefined;
    var result_exponent: i32 = undefined;
    var result: u128 = undefined;

    if (exponent_gap == 0 and product > addend_wide) {
        result_negative = product_negative;
        result_exponent = product_exponent;
        result = product - addend_wide;
    } else if (exponent_gap <= 0) {
        result_negative = !product_negative;
        result_exponent = addend.exponent - target_point;
        result = addend_wide - stickyRight(product, -exponent_gap);
    } else {
        result_negative = product_negative;
        result_exponent = product_exponent;
        result = product - stickyRight(addend_wide, exponent_gap);
    }

    const upper = @truncate(u64, result >> 64);
    if (upper == 0) {
        return float_parts.WideFloatParts{
            .negative = result_negative,
            .exponent = result_exponent,
            .significand = @truncate(u64, result),
        };
    }

    const needed = target_point - highBit64(upper);
    result = shiftLeft(result, needed);
    return packWide(result_negative, result_exponent - needed, result);
}

pub fn mulAdd32(addend: u32, left: u32, right: u32, control: float_control.Control, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u32 {
    const addend_analysis = try float_parts.splitFloat32(addend, control, status);
    const left_analysis = try float_parts.splitFloat32(left, control, status);
    const right_analysis = try float_parts.splitFloat32(right, control, status);
    const addend_infinity = addend_analysis.kind == .infinity;
    const left_infinity = left_analysis.kind == .infinity;
    const right_infinity = right_analysis.kind == .infinity;
    const addend_zero = addend_analysis.kind == .zero;
    const left_zero = left_analysis.kind == .zero;
    const right_zero = right_analysis.kind == .zero;
    const maybe_nan = try a64_float_nan.processTernaryNan32(control, addend, left, right, status);

    if (addend_analysis.kind == .quiet_nan and ((left_infinity and right_zero) or (left_zero and right_infinity))) {
        try float_exception.processFloatException(.invalid_operation, control, status);
        return float_format.Binary32.defaultNan();
    }
    if (maybe_nan) |nan| {
        return nan;
    }

    const product_negative = left_analysis.negative != right_analysis.negative;
    const product_infinity = left_infinity or right_infinity;
    const product_zero = left_zero or right_zero;

    if ((left_infinity and right_zero) or (left_zero and right_infinity) or (addend_infinity and product_infinity and addend_analysis.negative != product_negative)) {
        try float_exception.processFloatException(.invalid_operation, control, status);
        return float_format.Binary32.defaultNan();
    }
    if ((addend_infinity and !addend_analysis.negative) or (product_infinity and !product_negative)) {
        return float_format.Binary32.infinity(false);
    }
    if ((addend_infinity and addend_analysis.negative) or (product_infinity and product_negative)) {
        return float_format.Binary32.infinity(true);
    }
    if (addend_zero and product_zero and addend_analysis.negative == product_negative) {
        return float_format.Binary32.zero(addend_analysis.negative);
    }

    const result = fusedParts(addend_analysis.parts, left_analysis.parts, right_analysis.parts);
    if (result.significand == 0) {
        return float_format.Binary32.zero(control.rounding() == .negative);
    }
    return try float_parts.roundFloat32(result, control, status);
}

pub fn mulAdd64(addend: u64, left: u64, right: u64, control: float_control.Control, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u64 {
    const addend_analysis = try float_parts.splitFloat64(addend, control, status);
    const left_analysis = try float_parts.splitFloat64(left, control, status);
    const right_analysis = try float_parts.splitFloat64(right, control, status);
    const addend_infinity = addend_analysis.kind == .infinity;
    const left_infinity = left_analysis.kind == .infinity;
    const right_infinity = right_analysis.kind == .infinity;
    const addend_zero = addend_analysis.kind == .zero;
    const left_zero = left_analysis.kind == .zero;
    const right_zero = right_analysis.kind == .zero;
    const maybe_nan = try a64_float_nan.processTernaryNan64(control, addend, left, right, status);

    if (addend_analysis.kind == .quiet_nan and ((left_infinity and right_zero) or (left_zero and right_infinity))) {
        try float_exception.processFloatException(.invalid_operation, control, status);
        return float_format.Binary64.defaultNan();
    }
    if (maybe_nan) |nan| {
        return nan;
    }

    const product_negative = left_analysis.negative != right_analysis.negative;
    const product_infinity = left_infinity or right_infinity;
    const product_zero = left_zero or right_zero;

    if ((left_infinity and right_zero) or (left_zero and right_infinity) or (addend_infinity and product_infinity and addend_analysis.negative != product_negative)) {
        try float_exception.processFloatException(.invalid_operation, control, status);
        return float_format.Binary64.defaultNan();
    }
    if ((addend_infinity and !addend_analysis.negative) or (product_infinity and !product_negative)) {
        return float_format.Binary64.infinity(false);
    }
    if ((addend_infinity and addend_analysis.negative) or (product_infinity and product_negative)) {
        return float_format.Binary64.infinity(true);
    }
    if (addend_zero and product_zero and addend_analysis.negative == product_negative) {
        return float_format.Binary64.zero(addend_analysis.negative);
    }

    const result = fusedParts(addend_analysis.parts, left_analysis.parts, right_analysis.parts);
    if (result.significand == 0) {
        return float_format.Binary64.zero(control.rounding() == .negative);
    }
    return try float_parts.roundFloat64(result, control, status);
}
