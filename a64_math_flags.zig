const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub const MathResult = struct {
    word: u64,
    carry: bool,
    overflow: bool,
};

pub const SaturatingIntegerResult = struct {
    value: u64,
    saturated: bool,
};

fn widthMask(width: u8) u64 {
    if (width >= 64) {
        return ~@as(u64, 0);
    }
    return (@as(u64, 1) << @intCast(u6, width)) - 1;
}

fn signedWidthValue(value: u64, width: u8) i128 {
    const mask = widthMask(width);
    const narrowed = value & mask;
    const high = @as(u64, 1) << @intCast(u6, width - 1);
    if ((narrowed & high) != 0) {
        return @as(i128, @bitCast(i64, narrowed | ~mask));
    }
    return @intCast(i128, narrowed);
}

fn signedWidthBits(value: i128, width: u8) u64 {
    return @bitCast(u64, @intCast(i64, value)) & widthMask(width);
}

pub fn mathAdd(wide: bool, left: u64, right: u64, carry_in: bool) MathResult {
    if (wide) {
        return mathAdd64(left, right, carry_in);
    }
    const result = mathAdd32(@intCast(u32, left), @intCast(u32, right), carry_in);
    return MathResult{
        .word = @as(u64, @intCast(u32, result.word)),
        .carry = result.carry,
        .overflow = result.overflow,
    };
}

pub fn mathSub(wide: bool, left: u64, right: u64, carry_in: bool) MathResult {
    return mathAdd(wide, left, ~right, carry_in);
}

pub fn integerMaximum(wide: bool, signed: bool, left: u64, right: u64) u64 {
    if (signed) {
        if (wide) {
            return if (@bitCast(i64, left) >= @bitCast(i64, right)) left else right;
        }
        return if (@bitCast(i32, @intCast(u32, left)) >= @bitCast(i32, @intCast(u32, right))) @as(u64, @intCast(u32, left)) else @as(u64, @intCast(u32, right));
    }
    if (wide) {
        return if (left >= right) left else right;
    }
    return if (@intCast(u32, left) >= @intCast(u32, right)) @as(u64, @intCast(u32, left)) else @as(u64, @intCast(u32, right));
}

pub fn integerMinimum(wide: bool, signed: bool, left: u64, right: u64) u64 {
    if (signed) {
        if (wide) {
            return if (@bitCast(i64, left) <= @bitCast(i64, right)) left else right;
        }
        return if (@bitCast(i32, @intCast(u32, left)) <= @bitCast(i32, @intCast(u32, right))) @as(u64, @intCast(u32, left)) else @as(u64, @intCast(u32, right));
    }
    if (wide) {
        return if (left <= right) left else right;
    }
    return if (@intCast(u32, left) <= @intCast(u32, right)) @as(u64, @intCast(u32, left)) else @as(u64, @intCast(u32, right));
}

pub fn signedSaturatedAdd(width: u8, left: u64, right: u64) SaturatingIntegerResult {
    const left_value = signedWidthValue(left, width);
    const right_value = signedWidthValue(right, width);
    const highest = (@as(i128, 1) << @intCast(u7, width - 1)) - 1;
    const lowest = -(@as(i128, 1) << @intCast(u7, width - 1));
    const result = left_value + right_value;
    if (result > highest) {
        return SaturatingIntegerResult{ .value = signedWidthBits(highest, width), .saturated = true };
    }
    if (result < lowest) {
        return SaturatingIntegerResult{ .value = signedWidthBits(lowest, width), .saturated = true };
    }
    return SaturatingIntegerResult{ .value = signedWidthBits(result, width), .saturated = false };
}

pub fn signedSaturatedSub(width: u8, left: u64, right: u64) SaturatingIntegerResult {
    const left_value = signedWidthValue(left, width);
    const right_value = signedWidthValue(right, width);
    const highest = (@as(i128, 1) << @intCast(u7, width - 1)) - 1;
    const lowest = -(@as(i128, 1) << @intCast(u7, width - 1));
    const result = left_value - right_value;
    if (result > highest) {
        return SaturatingIntegerResult{ .value = signedWidthBits(highest, width), .saturated = true };
    }
    if (result < lowest) {
        return SaturatingIntegerResult{ .value = signedWidthBits(lowest, width), .saturated = true };
    }
    return SaturatingIntegerResult{ .value = signedWidthBits(result, width), .saturated = false };
}

pub fn signedSaturatedDoublingMultiplyHigh(width: u8, left: u64, right: u64) SaturatingIntegerResult {
    const left_value = signedWidthValue(left, width);
    const right_value = signedWidthValue(right, width);
    const highest = (@as(i128, 1) << @intCast(u7, width - 1)) - 1;
    const lowest = -(@as(i128, 1) << @intCast(u7, width - 1));
    const doubled = left_value * right_value * 2;
    const result = doubled >> @intCast(u7, width);
    if (result > highest) {
        return SaturatingIntegerResult{ .value = signedWidthBits(highest, width), .saturated = true };
    }
    if (result < lowest) {
        return SaturatingIntegerResult{ .value = signedWidthBits(lowest, width), .saturated = true };
    }
    return SaturatingIntegerResult{ .value = signedWidthBits(result, width), .saturated = false };
}

pub fn unsignedSaturatedAdd(width: u8, left: u64, right: u64) SaturatingIntegerResult {
    const mask = widthMask(width);
    const result = @as(u128, left & mask) + @as(u128, right & mask);
    if (result > mask) {
        return SaturatingIntegerResult{ .value = mask, .saturated = true };
    }
    return SaturatingIntegerResult{ .value = @intCast(u64, result), .saturated = false };
}

pub fn unsignedSaturatedSub(width: u8, left: u64, right: u64) SaturatingIntegerResult {
    const left_value = left & widthMask(width);
    const right_value = right & widthMask(width);
    if (left_value < right_value) {
        return SaturatingIntegerResult{ .value = 0, .saturated = true };
    }
    return SaturatingIntegerResult{ .value = left_value - right_value, .saturated = false };
}

pub fn mathAdd32(left: u32, right: u32, carry_in: bool) MathResult {
    const carry: u64 = if (carry_in) 1 else 0;
    const wide = @as(u64, left) + @as(u64, right) + carry;
    const result = @intCast(u32, wide & 0xffffffff);
    const overflow = ((~(left ^ right) & (left ^ result)) & 0x80000000) != 0;
    return MathResult{
        .word = @as(u64, result),
        .carry = wide > 0xffffffff,
        .overflow = overflow,
    };
}

pub fn mathAdd64(left: u64, right: u64, carry_in: bool) MathResult {
    const carry: u128 = if (carry_in) 1 else 0;
    const wide = @as(u128, left) + @as(u128, right) + carry;
    const result = @intCast(u64, wide & 0xffffffffffffffff);
    const overflow = ((~(left ^ right) & (left ^ result)) & 0x8000000000000000) != 0;
    return MathResult{
        .word = result,
        .carry = wide > 0xffffffffffffffff,
        .overflow = overflow,
    };
}
