const a64_state = @import("a64_state.zig");
const math_flags = @import("a64_math_flags.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub const SaturatingVectorResult = struct {
    value: u64,
    saturated: bool,
};

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

pub fn saturatingVectorLanes(left: u64, right: u64, lane: u8, signed: bool, add: bool) SaturatingVectorResult {
    const mask = ones(lane);
    var result = SaturatingVectorResult{ .value = 0, .saturated = false };
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_lane = (left >> amount) & mask;
        const right_lane = (right >> amount) & mask;
        const saturated = if (signed)
            if (add)
                math_flags.signedSaturatedAdd(lane, left_lane, right_lane)
            else
                math_flags.signedSaturatedSub(lane, left_lane, right_lane)
        else if (add)
            math_flags.unsignedSaturatedAdd(lane, left_lane, right_lane)
        else
            math_flags.unsignedSaturatedSub(lane, left_lane, right_lane);
        result.value |= (saturated.value & mask) << amount;
        result.saturated = result.saturated or saturated.saturated;
    }
    return result;
}

pub fn signedSaturatingAccumulateUnsignedVectorLanes(left: u64, right: u64, lane: u8) SaturatingVectorResult {
    const mask = ones(lane);
    const highest = (@as(i128, 1) << @intCast(u7, lane - 1)) - 1;
    const lowest = -(@as(i128, 1) << @intCast(u7, lane - 1));
    var result = SaturatingVectorResult{ .value = 0, .saturated = false };
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_lane = @intCast(i128, (left >> amount) & mask);
        const right_raw = (right >> amount) & mask;
        const right_lane = if (lane == 64)
            @intCast(i128, @bitCast(i64, right_raw))
        else
            @intCast(i128, @bitCast(i64, signExtendRuntime(right_raw, @intCast(u6, lane))));
        var sum = left_lane + right_lane;
        if (sum > highest) {
            sum = highest;
            result.saturated = true;
        } else if (sum < lowest) {
            sum = lowest;
            result.saturated = true;
        }
        result.value |= (@bitCast(u64, @intCast(i64, sum)) & mask) << amount;
    }
    return result;
}

pub fn unsignedSaturatingAccumulateSignedVectorLanes(left: u64, right: u64, lane: u8) SaturatingVectorResult {
    const mask = ones(lane);
    var result = SaturatingVectorResult{ .value = 0, .saturated = false };
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_raw = (left >> amount) & mask;
        const left_lane = if (lane == 64)
            @intCast(i128, @bitCast(i64, left_raw))
        else
            @intCast(i128, @bitCast(i64, signExtendRuntime(left_raw, @intCast(u6, lane))));
        const right_lane = @intCast(i128, (right >> amount) & mask);
        var sum = left_lane + right_lane;
        if (sum > @intCast(i128, mask)) {
            sum = @intCast(i128, mask);
            result.saturated = true;
        } else if (sum < 0) {
            sum = 0;
            result.saturated = true;
        }
        result.value |= (@intCast(u64, sum) & mask) << amount;
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

pub fn signedSaturatingAbsoluteVectorLanes(value: u64, lane: u8) SaturatingVectorResult {
    const sign = @as(u64, 1) << @intCast(u6, lane - 1);
    const high = sign - 1;
    if (lane == 64) {
        if (value == sign) {
            return SaturatingVectorResult{ .value = high, .saturated = true };
        }
        return SaturatingVectorResult{
            .value = if ((value & sign) != 0) 0 -% value else value,
            .saturated = false,
        };
    }

    const mask = ones(lane);
    var result = SaturatingVectorResult{ .value = 0, .saturated = false };
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const element = (value >> amount) & mask;
        const magnitude = if (element == sign) blk: {
            result.saturated = true;
            break :blk high;
        } else if ((element & sign) != 0) 0 -% element else element;
        result.value |= (magnitude & mask) << amount;
    }
    return result;
}

pub fn signedSaturatingNegateVectorLanes(value: u64, lane: u8) SaturatingVectorResult {
    const sign = @as(u64, 1) << @intCast(u6, lane - 1);
    const high = sign - 1;
    if (lane == 64) {
        if (value == sign) {
            return SaturatingVectorResult{ .value = high, .saturated = true };
        }
        return SaturatingVectorResult{
            .value = 0 -% value,
            .saturated = false,
        };
    }

    const mask = ones(lane);
    var result = SaturatingVectorResult{ .value = 0, .saturated = false };
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const element = (value >> amount) & mask;
        const negated = if (element == sign) blk: {
            result.saturated = true;
            break :blk high;
        } else 0 -% element;
        result.value |= (negated & mask) << amount;
    }
    return result;
}

pub fn signedSaturatingDoublingMultiplyHighVectorLanes(left: u64, right: u64, lane: u8) SaturatingVectorResult {
    const mask = ones(lane);
    const highest = (@as(i128, 1) << @intCast(u7, lane - 1)) - 1;
    const lowest = -(@as(i128, 1) << @intCast(u7, lane - 1));
    var result = SaturatingVectorResult{ .value = 0, .saturated = false };
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_lane = @intCast(i128, @bitCast(i64, signExtendRuntime((left >> amount) & mask, @intCast(u6, lane))));
        const right_lane = @intCast(i128, @bitCast(i64, signExtendRuntime((right >> amount) & mask, @intCast(u6, lane))));
        const doubled = left_lane * right_lane * 2;
        var lane_result = doubled >> @intCast(u7, lane);
        if (lane_result > highest) {
            lane_result = highest;
            result.saturated = true;
        } else if (lane_result < lowest) {
            lane_result = lowest;
            result.saturated = true;
        }
        result.value |= (@bitCast(u64, @intCast(i64, lane_result)) & mask) << amount;
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
