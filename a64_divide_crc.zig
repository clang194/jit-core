const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub fn unsignedDivideSized(wide: bool, left: u64, right: u64) u64 {
    if (right == 0) {
        return 0;
    }

    if (wide) {
        return @divTrunc(left, right);
    }
    return @as(u64, @divTrunc(@intCast(u32, left), @intCast(u32, right)));
}

pub fn signedDivideSized(wide: bool, left: u64, right: u64) u64 {
    if (wide) {
        const divisor = @bitCast(i64, right);
        if (divisor == 0) {
            return 0;
        }

        const dividend = @bitCast(i64, left);
        if (dividend == @as(i64, -9223372036854775808) and divisor == -1) {
            return left;
        }
        return @bitCast(u64, @divTrunc(dividend, divisor));
    }

    const divisor = @bitCast(i32, @intCast(u32, right));
    if (divisor == 0) {
        return 0;
    }

    const dividend = @bitCast(i32, @intCast(u32, left));
    if (dividend == @as(i32, -2147483648) and divisor == -1) {
        return @as(u64, @intCast(u32, dividend));
    }
    return @as(u64, @intCast(u32, @divTrunc(dividend, divisor)));
}

pub fn crc32(crc: u32, value: u64, bytes: u4) u32 {
    return crc32WithPolynomial(crc, value, bytes, 0xedb88320);
}

pub fn crc32c(crc: u32, value: u64, bytes: u4) u32 {
    return crc32WithPolynomial(crc, value, bytes, 0x82f63b78);
}

pub fn crc32WithPolynomial(crc: u32, value: u64, bytes: u4, polynomial: u32) u32 {
    var result = crc;
    var remaining = value;
    var byte_index: u4 = 0;
    while (byte_index < bytes) : (byte_index += 1) {
        result ^= @intCast(u32, remaining & 0xff);
        var bit_index: u4 = 0;
        while (bit_index < 8) : (bit_index += 1) {
            const mask = if ((result & 1) != 0) polynomial else @as(u32, 0);
            result = (result >> 1) ^ mask;
        }
        remaining >>= 8;
    }
    return result;
}
