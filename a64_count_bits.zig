const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub fn countLeadingZeroes32(value: u32) u32 {
    if (value == 0) {
        return 32;
    }

    var count: u32 = 0;
    var mask: u32 = 0x80000000;
    while ((value & mask) == 0) : (mask >>= 1) {
        count += 1;
    }
    return count;
}

pub fn countLeadingZeroes64(value: u64) u64 {
    if (value == 0) {
        return 64;
    }

    var count: u64 = 0;
    var mask: u64 = 0x8000000000000000;
    while ((value & mask) == 0) : (mask >>= 1) {
        count += 1;
    }
    return count;
}

pub fn countLeadingZeroesVectorLanes(value: u64, lane: u8) u64 {
    const mask = (@as(u64, 1) << @intCast(u6, lane)) - 1;
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const element = (value >> amount) & mask;
        const count = if (lane == 8)
            @as(u64, @clz(u8, @intCast(u8, element)))
        else if (lane == 16)
            @as(u64, @clz(u16, @intCast(u16, element)))
        else
            @as(u64, @clz(u32, @intCast(u32, element)));
        result |= count << amount;
    }
    return result;
}

pub fn countLeadingSignBits32(value: u32) u32 {
    const folded = if ((value & 0x80000000) != 0) ~value else value;
    return countLeadingZeroes32(folded) - 1;
}

pub fn countLeadingSignBits64(value: u64) u64 {
    const folded = if ((value & 0x8000000000000000) != 0) ~value else value;
    return countLeadingZeroes64(folded) - 1;
}

pub fn reverseByteBits(value: u8) u8 {
    var remaining = value;
    var result: u8 = 0;
    var index: u8 = 0;
    while (index < 8) : (index += 1) {
        result = (result << 1) | (remaining & 1);
        remaining >>= 1;
    }
    return result;
}

pub fn reverseVectorByteBits(value: u64) u64 {
    var result: u64 = 0;
    var index: u8 = 0;
    while (index < 8) : (index += 1) {
        const shift = @intCast(u6, index * 8);
        result |= @as(u64, reverseByteBits(@intCast(u8, (value >> shift) & 0xff))) << shift;
    }
    return result;
}
