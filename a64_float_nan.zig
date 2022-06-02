const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub fn isDenormal32(value: u32) bool {
    const magnitude = value & 0x7fffffff;
    return magnitude != 0 and magnitude <= 0x007fffff;
}

pub fn isDenormal64(value: u64) bool {
    const magnitude = value & 0x7fffffffffffffff;
    return magnitude != 0 and magnitude <= 0x000fffffffffffff;
}

pub fn isNan32(value: u32) bool {
    return (value & 0x7fffffff) > 0x7f800000;
}

pub fn isNan64(value: u64) bool {
    return (value & 0x7fffffffffffffff) > 0x7ff0000000000000;
}

pub fn isQuietNan32(value: u32) bool {
    return (value & 0x7fc00000) == 0x7fc00000;
}

pub fn isSignalingNan32(value: u32) bool {
    return (value & 0x7fc00000) == 0x7f800000 and (value & 0x007fffff) != 0;
}

pub fn isQuietNan64(value: u64) bool {
    return (value & 0x7ff8000000000000) == 0x7ff8000000000000;
}

pub fn isSignalingNan64(value: u64) bool {
    return (value & 0x7ff8000000000000) == 0x7ff0000000000000 and (value & 0x0007ffffffffffff) != 0;
}

pub fn chooseBinaryNan32(control: a64_state.FloatControl, mode: FloatNanMode64, left: u32, right: u32) ?u32 {
    if (!useAccurateNan(mode) or control.dn()) {
        return null;
    }
    if (isSignalingNan32(left)) {
        return left | 0x00400000;
    }
    if (isSignalingNan32(right)) {
        return right | 0x00400000;
    }
    if (isQuietNan32(left)) {
        return left;
    }
    if (isQuietNan32(right)) {
        return right;
    }
    return null;
}

pub fn chooseBinaryNan64(control: a64_state.FloatControl, mode: FloatNanMode64, left: u64, right: u64) ?u64 {
    if (!useAccurateNan(mode) or control.dn()) {
        return null;
    }
    if (isSignalingNan64(left)) {
        return left | 0x0008000000000000;
    }
    if (isSignalingNan64(right)) {
        return right | 0x0008000000000000;
    }
    if (isQuietNan64(left)) {
        return left;
    }
    if (isQuietNan64(right)) {
        return right;
    }
    return null;
}

pub fn chooseTernaryNan32(control: a64_state.FloatControl, mode: FloatNanMode64, first: u32, second: u32, third: u32) ?u32 {
    if (!useAccurateNan(mode) or control.dn()) {
        return null;
    }
    if (isSignalingNan32(first)) {
        return first | 0x00400000;
    }
    if (isSignalingNan32(second)) {
        return second | 0x00400000;
    }
    if (isSignalingNan32(third)) {
        return third | 0x00400000;
    }
    if (isQuietNan32(first)) {
        return first;
    }
    if (isQuietNan32(second)) {
        return second;
    }
    if (isQuietNan32(third)) {
        return third;
    }
    return null;
}

pub fn chooseTernaryNan64(control: a64_state.FloatControl, mode: FloatNanMode64, first: u64, second: u64, third: u64) ?u64 {
    if (!useAccurateNan(mode) or control.dn()) {
        return null;
    }
    if (isSignalingNan64(first)) {
        return first | 0x0008000000000000;
    }
    if (isSignalingNan64(second)) {
        return second | 0x0008000000000000;
    }
    if (isSignalingNan64(third)) {
        return third | 0x0008000000000000;
    }
    if (isQuietNan64(first)) {
        return first;
    }
    if (isQuietNan64(second)) {
        return second;
    }
    if (isQuietNan64(third)) {
        return third;
    }
    return null;
}

pub fn chooseUnaryNan32(control: a64_state.FloatControl, mode: FloatNanMode64, value: u32) ?u32 {
    if (!useAccurateNan(mode) or control.dn()) {
        return null;
    }
    if (isSignalingNan32(value)) {
        return value | 0x00400000;
    }
    if (isQuietNan32(value)) {
        return value;
    }
    return null;
}

pub fn chooseUnaryNan64(control: a64_state.FloatControl, mode: FloatNanMode64, value: u64) ?u64 {
    if (!useAccurateNan(mode) or control.dn()) {
        return null;
    }
    if (isSignalingNan64(value)) {
        return value | 0x0008000000000000;
    }
    if (isQuietNan64(value)) {
        return value;
    }
    return null;
}
