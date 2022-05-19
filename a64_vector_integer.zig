const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub fn addVectorLanes(left: u64, right: u64, lane: u8) u64 {
    if (lane == 64) {
        return left +% right;
    }

    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const sum = ((left >> amount) & mask) +% ((right >> amount) & mask);
        result |= (sum & mask) << amount;
    }
    return result;
}

pub fn subtractVectorLanes(left: u64, right: u64, lane: u8) u64 {
    if (lane == 64) {
        return left -% right;
    }

    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const difference = ((left >> amount) & mask) -% ((right >> amount) & mask);
        result |= (difference & mask) << amount;
    }
    return result;
}

pub fn signedHalvingAddVectorLanes(left: u64, right: u64, lane: u8) u64 {
    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_lane = @bitCast(i64, signExtendRuntime((left >> amount) & mask, @intCast(u6, lane)));
        const right_lane = @bitCast(i64, signExtendRuntime((right >> amount) & mask, @intCast(u6, lane)));
        const halved = @bitCast(u64, (left_lane + right_lane) >> 1);
        result |= (halved & mask) << amount;
    }
    return result;
}

pub fn signedRoundingHalvingAddVectorLanes(left: u64, right: u64, lane: u8) u64 {
    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_lane = @bitCast(i64, signExtendRuntime((left >> amount) & mask, @intCast(u6, lane)));
        const right_lane = @bitCast(i64, signExtendRuntime((right >> amount) & mask, @intCast(u6, lane)));
        const halved = @bitCast(u64, (left_lane + right_lane + 1) >> 1);
        result |= (halved & mask) << amount;
    }
    return result;
}

pub fn signedHalvingSubtractVectorLanes(left: u64, right: u64, lane: u8) u64 {
    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_lane = @bitCast(i64, signExtendRuntime((left >> amount) & mask, @intCast(u6, lane)));
        const right_lane = @bitCast(i64, signExtendRuntime((right >> amount) & mask, @intCast(u6, lane)));
        const halved = @bitCast(u64, (left_lane - right_lane) >> 1);
        result |= (halved & mask) << amount;
    }
    return result;
}

pub fn halvingAddVectorLanes(left: u64, right: u64, lane: u8) u64 {
    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_lane = (left >> amount) & mask;
        const right_lane = (right >> amount) & mask;
        result |= (((left_lane + right_lane) >> 1) & mask) << amount;
    }
    return result;
}

pub fn roundingHalvingAddVectorLanes(left: u64, right: u64, lane: u8) u64 {
    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_lane = (left >> amount) & mask;
        const right_lane = (right >> amount) & mask;
        result |= (((left_lane + right_lane + 1) >> 1) & mask) << amount;
    }
    return result;
}

pub fn halvingSubtractVectorLanes(left: u64, right: u64, lane: u8) u64 {
    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_lane = @intCast(i64, (left >> amount) & mask);
        const right_lane = @intCast(i64, (right >> amount) & mask);
        const halved = @bitCast(u64, (left_lane - right_lane) >> 1);
        result |= (halved & mask) << amount;
    }
    return result;
}

pub fn differenceUnsignedVectorLanes(left: u64, right: u64, lane: u8) u64 {
    if (lane == 64) {
        return if (left >= right) left - right else right - left;
    }

    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_lane = (left >> amount) & mask;
        const right_lane = (right >> amount) & mask;
        const difference = if (left_lane >= right_lane) left_lane - right_lane else right_lane - left_lane;
        result |= difference << amount;
    }
    return result;
}

pub fn differenceSignedVectorLanes(left: u64, right: u64, lane: u8) u64 {
    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_lane = @bitCast(i64, signExtendRuntime((left >> amount) & mask, @intCast(u6, lane)));
        const right_lane = @bitCast(i64, signExtendRuntime((right >> amount) & mask, @intCast(u6, lane)));
        const difference = if (left_lane >= right_lane) left_lane - right_lane else right_lane - left_lane;
        result |= (@bitCast(u64, difference) & mask) << amount;
    }
    return result;
}

pub fn absoluteVectorLanes(value: u64, lane: u8) u64 {
    if (lane == 64) {
        return if ((value & (@as(u64, 1) << 63)) != 0) 0 -% value else value;
    }

    const mask = ones(lane);
    const sign = @as(u64, 1) << @intCast(u6, lane - 1);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const element = (value >> amount) & mask;
        const magnitude = if ((element & sign) != 0) 0 -% element else element;
        result |= (magnitude & mask) << amount;
    }
    return result;
}

pub fn multiplyVectorLanes(left: u64, right: u64, lane: u8) u64 {
    if (lane == 64) {
        return left *% right;
    }

    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const product = ((left >> amount) & mask) *% ((right >> amount) & mask);
        result |= (product & mask) << amount;
    }
    return result;
}

pub fn countVectorBytes(value: u64) u64 {
    var result: u64 = 0;
    var index: u8 = 0;
    while (index < 8) : (index += 1) {
        const shift = @intCast(u6, index * 8);
        result |= @as(u64, countByteBits(@intCast(u8, (value >> shift) & 0xff))) << shift;
    }
    return result;
}

pub fn countByteBits(value: u8) u8 {
    var remaining = value;
    var count: u8 = 0;
    while (remaining != 0) : (remaining >>= 1) {
        count += remaining & 1;
    }
    return count;
}
