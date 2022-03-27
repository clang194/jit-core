const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub fn expandVectorImmediate(op: bool, cmode: u4, imm8: u8) u64 {
    const value = @as(u64, imm8);
    switch (cmode >> 1) {
        0 => return replicate64(value, 32),
        1 => return replicate64(value << 8, 32),
        2 => return replicate64(value << 16, 32),
        3 => return replicate64(value << 24, 32),
        4 => return replicate64(value, 16),
        5 => return replicate64(value << 8, 16),
        6 => {
            if ((cmode & 1) == 0) {
                return replicate64((value << 8) | 0xff, 32);
            }
            return replicate64((value << 16) | 0xffff, 32);
        },
        else => {
            if ((cmode & 1) == 0 and !op) {
                return replicate64(value, 8);
            }
            if ((cmode & 1) == 0 and op) {
                var result: u64 = 0;
                var index: u3 = 0;
                while (index < 8) : (index += 1) {
                    if (((imm8 >> index) & 1) != 0) {
                        result |= @as(u64, 0xff) << @intCast(u6, @as(u16, index) * 8);
                    }
                }
                return result;
            }
            if (!op) {
                var result: u64 = 0;
                result |= if ((imm8 & 0x80) != 0) @as(u64, 0x80000000) else 0;
                result |= if ((imm8 & 0x40) != 0) @as(u64, 0x3e000000) else @as(u64, 0x40000000);
                result |= @as(u64, imm8 & 0x3f) << 19;
                return replicate64(result, 32);
            }
            var result: u64 = 0;
            result |= if ((imm8 & 0x80) != 0) @as(u64, 0x8000000000000000) else 0;
            result |= if ((imm8 & 0x40) != 0) @as(u64, 0x3fc0000000000000) else @as(u64, 0x4000000000000000);
            result |= @as(u64, imm8 & 0x3f) << 48;
            return result;
        },
    }
}

pub fn expandVectorHalfFloatImmediate(imm8: u8) u64 {
    var imm16: u16 = 0;
    imm16 |= if ((imm8 & 0x80) != 0) @as(u16, 0x8000) else 0;
    imm16 |= if ((imm8 & 0x40) != 0) @as(u16, 0x3000) else @as(u16, 0x4000);
    imm16 |= @as(u16, imm8 & 0x3f) << 6;
    return replicate64(imm16, 16);
}

pub fn rotateRight64(value: u64, amount: u6) u64 {
    const shift = amount & 63;
    if (shift == 0) {
        return value;
    }
    return (value >> shift) | (value << @intCast(u6, 64 - shift));
}

pub fn rotateRightSized(wide: bool, value: u64, amount: u6) u64 {
    if (wide) {
        return rotateRight64(value, amount);
    }
    return @as(u64, rotateRight32(@intCast(u32, value), @intCast(u5, amount & 31)));
}

pub fn extractRegisterBits(wide: bool, lower: u64, upper: u64, amount: u6) u64 {
    if (amount == 0) {
        return lower;
    }

    if (wide) {
        return (lower >> amount) | (upper << @intCast(u6, 64 - amount));
    }

    const shift = @intCast(u5, amount);
    return @as(u64, (@intCast(u32, lower) >> shift) | (@intCast(u32, upper) << @intCast(u5, 32 - shift)));
}

pub fn reverseHalfBytes(value: u64) u64 {
    return ((value & 0x00ff00ff00ff00ff) << 8) | ((value & 0xff00ff00ff00ff00) >> 8);
}

pub fn reverseBytes32(value: u32) u32 {
    return ((value & 0x000000ff) << 24) |
        ((value & 0x0000ff00) << 8) |
        ((value & 0x00ff0000) >> 8) |
        ((value & 0xff000000) >> 24);
}

pub fn reverseWordBytes(value: u64) u64 {
    return @as(u64, reverseBytes32(@intCast(u32, value))) |
        (@as(u64, reverseBytes32(@intCast(u32, value >> 32))) << 32);
}

pub fn reverseWordHalfwords(value: u64) u64 {
    return ((value & 0x0000ffff0000ffff) << 16) | ((value & 0xffff0000ffff0000) >> 16);
}

pub fn reverseDoublewordHalfwords(value: u64) u64 {
    return ((value & 0x000000000000ffff) << 48) |
        ((value & 0x00000000ffff0000) << 16) |
        ((value & 0x0000ffff00000000) >> 16) |
        ((value & 0xffff000000000000) >> 48);
}

pub fn reverseDoublewordWords(value: u64) u64 {
    return (value << 32) | (value >> 32);
}

pub fn reverseBytes64(value: u64) u64 {
    return (@as(u64, reverseBytes32(@intCast(u32, value))) << 32) |
        @as(u64, reverseBytes32(@intCast(u32, value >> 32)));
}

pub fn reverseBits32(value: u32) u32 {
    var result = ((value & 0x55555555) << 1) | ((value >> 1) & 0x55555555);
    result = ((result & 0x33333333) << 2) | ((result >> 2) & 0x33333333);
    result = ((result & 0x0f0f0f0f) << 4) | ((result >> 4) & 0x0f0f0f0f);
    return reverseBytes32(result);
}

pub fn reverseBits64(value: u64) u64 {
    return (@as(u64, reverseBits32(@intCast(u32, value))) << 32) |
        @as(u64, reverseBits32(@intCast(u32, value >> 32)));
}

pub fn lowestSetBit5(value: u5) u3 {
    var probe = value;
    var bit: u3 = 0;
    while ((probe & 1) == 0) {
        probe >>= 1;
        bit += 1;
    }
    return bit;
}

pub fn spreadVectorElement(value: u64, lane: u8) u64 {
    if (lane == 64) {
        return value;
    }

    const lane_value = value & ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        result |= lane_value << @intCast(u6, shift);
    }
    return result;
}

pub fn signExtendRuntime(value: u64, width: u6) u64 {
    const high = @as(u64, 1) << @intCast(u6, width - 1);
    const mask = ones(width);
    const narrowed = value & mask;
    if ((narrowed & high) != 0) {
        return narrowed | ~mask;
    }
    return narrowed;
}
