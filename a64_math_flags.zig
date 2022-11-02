const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub const MathResult = struct {
    word: u64,
    carry: bool,
    overflow: bool,
};

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
