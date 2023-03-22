const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_trace_flow.zig");
usingnamespace @import("thumb_run_flow.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_memory_flow.zig");

pub fn pushMask(word: u16) u16 {
    var mask = word & 0xff;
    if ((word & 0x0100) != 0) {
        mask |= @as(u16, 1) << 14;
    }
    return mask;
}

pub fn popMask(word: u16) u16 {
    var mask = word & 0xff;
    if ((word & 0x0100) != 0) {
        mask |= @as(u16, 1) << 15;
    }
    return mask;
}

pub fn signExtendHalf(value: u32) u32 {
    return @bitCast(u32, bits.signExtend32(value, 16));
}

pub fn signExtendByte(value: u32) u32 {
    return @bitCast(u32, bits.signExtend32(value, 8));
}

pub fn byteReverseWord(value: u32) u32 {
    return bits.swapBytes32(value);
}

pub fn byteReverseHalf(value: u32) u32 {
    return bits.swapBytes16(@intCast(u16, value));
}

pub fn byteReverseHalfwords(value: u32) u32 {
    return bits.swapLaneBytes32(value);
}
