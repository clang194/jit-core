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

pub fn countLeadingSignBits32(value: u32) u32 {
    const folded = if ((value & 0x80000000) != 0) ~value else value;
    return countLeadingZeroes32(folded) - 1;
}

pub fn countLeadingSignBits64(value: u64) u64 {
    const folded = if ((value & 0x8000000000000000) != 0) ~value else value;
    return countLeadingZeroes64(folded) - 1;
}
