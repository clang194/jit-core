const a64_float_nan = @import("a64_float_nan.zig");
const float_control = @import("float_control.zig");
const float_exception = @import("float_exception.zig");
const float_format = @import("float_format.zig");
const float_parts = @import("float_parts.zig");
const float_status = @import("float_status.zig");

const target_point: i32 = float_parts.normalized_point;

fn highBit64(value: u64) i32 {
    return @intCast(i32, 63 - @clz(value));
}

fn bit128(value: u128, comptime index: usize) bool {
    if (index >= 128) {
        @compileError("invalid bit index");
    }
    return ((value >> @intCast(u7, index)) & 1) != 0;
}

fn highBit128(value: u128) i32 {
    const upper = @truncate(u64, value >> 64);
    if (upper != 0) {
        return 64 + highBit64(upper);
    }
    return highBit64(@truncate(u64, value));
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
        .exponent = exponent + 2,
        .significand = @truncate(u64, value >> 64) | if (lower == 0) @as(u64, 0) else @as(u64, 1),
    };
}

pub fn fusedParts(addend_input: float_parts.WideFloatParts, left_input: float_parts.WideFloatParts, right_input: float_parts.WideFloatParts) float_parts.WideFloatParts {
    if (left_input.significand == 0 or right_input.significand == 0) {
        return addend_input;
    }

    const product_negative = left_input.negative != right_input.negative;
    var product_exponent = left_input.exponent + right_input.exponent;
    var product = @as(u128, left_input.significand) * @as(u128, right_input.significand);

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

    const exponent_gap = product_exponent - addend_input.exponent;
    if (product_negative == addend_input.negative) {
        if (exponent_gap <= 0) {
            return float_parts.WideFloatParts{
                .negative = addend_input.negative,
                .exponent = addend_input.exponent,
                .significand = addend_input.significand + @truncate(u64, stickyRight(product, target_point - exponent_gap)),
            };
        }
        const result = product + stickyRight(@as(u128, addend_input.significand), exponent_gap - target_point);
        return packWide(product_negative, product_exponent, result);
    }

    const addend_wide = @as(u128, addend_input.significand) << @intCast(u7, target_point);
    var result_negative: bool = undefined;
    var result_exponent: i32 = undefined;
    var result: u128 = undefined;

    if (exponent_gap == 0 and product > addend_wide) {
        result_negative = product_negative;
        result_exponent = product_exponent;
        result = product - addend_wide;
    } else if (exponent_gap <= 0) {
        result_negative = !product_negative;
        result_exponent = addend_input.exponent;
        result = addend_wide - stickyRight(product, -exponent_gap);
    } else {
        result_negative = product_negative;
        result_exponent = product_exponent;
        result = product - stickyRight(addend_wide, exponent_gap);
    }

    if (result == 0) {
        return float_parts.WideFloatParts{ .negative = result_negative, .exponent = 0, .significand = 0 };
    }

    const needed = target_point + 64 - highBit128(result);
    result = shiftLeft(result, needed);
    return packWide(result_negative, result_exponent - needed, result);
}

pub fn mulAdd16(addend: u16, left: u16, right: u16, control: float_control.Control, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u16 {
    const addend_analysis = try float_parts.splitFloat16(addend, control, status);
    const left_analysis = try float_parts.splitFloat16(left, control, status);
    const right_analysis = try float_parts.splitFloat16(right, control, status);
    const addend_infinity = addend_analysis.kind == .infinity;
    const left_infinity = left_analysis.kind == .infinity;
    const right_infinity = right_analysis.kind == .infinity;
    const addend_zero = addend_analysis.kind == .zero;
    const left_zero = left_analysis.kind == .zero;
    const right_zero = right_analysis.kind == .zero;
    const maybe_nan = try a64_float_nan.processTernaryNan16(control, addend, left, right, status);

    if (addend_analysis.kind == .quiet_nan and ((left_infinity and right_zero) or (left_zero and right_infinity))) {
        try float_exception.processFloatException(.invalid_operation, control, status);
        return float_format.Binary16.defaultNan();
    }
    if (maybe_nan) |nan| {
        return nan;
    }

    const product_negative = left_analysis.negative != right_analysis.negative;
    const product_infinity = left_infinity or right_infinity;
    const product_zero = left_zero or right_zero;

    if ((left_infinity and right_zero) or (left_zero and right_infinity) or (addend_infinity and product_infinity and addend_analysis.negative != product_negative)) {
        try float_exception.processFloatException(.invalid_operation, control, status);
        return float_format.Binary16.defaultNan();
    }
    if ((addend_infinity and !addend_analysis.negative) or (product_infinity and !product_negative)) {
        return float_format.Binary16.infinity(false);
    }
    if ((addend_infinity and addend_analysis.negative) or (product_infinity and product_negative)) {
        return float_format.Binary16.infinity(true);
    }
    if (addend_zero and product_zero and addend_analysis.negative == product_negative) {
        return float_format.Binary16.zero(addend_analysis.negative);
    }

    const result = fusedParts(addend_analysis.parts, left_analysis.parts, right_analysis.parts);
    if (result.significand == 0) {
        return float_format.Binary16.zero(control.rounding() == .negative);
    }
    return try float_parts.roundFloat16(result, control, status);
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
