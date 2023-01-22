const a64_state = @import("a64_state.zig");
const a64_immediate_vectors = @import("a64_immediate_vectors.zig");
const a64_logic_masks = @import("a64_logic_masks.zig");
const math_flags = @import("a64_math_flags.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;
const ones = a64_logic_masks.ones;
const signExtendRuntime = a64_immediate_vectors.signExtendRuntime;

pub const SaturatingVectorResult = struct {
    value: u64,
    saturated: bool,
};

pub const LaneProductParts = struct {
    high: u64,
    low: u64,
};

pub const VectorProductParts = struct {
    high: a64_state.VectorValue,
    low: a64_state.VectorValue,
};

pub const SaturatingProductParts = struct {
    high: u64,
    low: u64,
    saturated: bool,
};

pub const VectorSaturatingProductParts = struct {
    high: a64_state.VectorValue,
    low: a64_state.VectorValue,
    saturated: bool,
};

pub const WideSaturatingVectorResult = struct {
    value: a64_state.VectorValue,
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
    const parts = signedSaturatingDoublingProductParts64(left, right, lane);
    return SaturatingVectorResult{ .value = parts.high, .saturated = parts.saturated };
}

pub fn signedSaturatingDoublingProductParts64(left: u64, right: u64, lane: u8) SaturatingProductParts {
    const mask = ones(lane);
    const highest = (@as(i128, 1) << @intCast(u7, lane - 1)) - 1;
    const lowest = -(@as(i128, 1) << @intCast(u7, lane - 1));
    var result = SaturatingProductParts{ .high = 0, .low = 0, .saturated = false };
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_lane = @intCast(i128, @bitCast(i64, signExtendRuntime((left >> amount) & mask, @intCast(u6, lane))));
        const right_lane = @intCast(i128, @bitCast(i64, signExtendRuntime((right >> amount) & mask, @intCast(u6, lane))));
        const doubled = left_lane * right_lane * 2;
        result.low |= @intCast(u64, @bitCast(u128, doubled) & @intCast(u128, mask)) << amount;
        var lane_result = doubled >> @intCast(u7, lane);
        if (lane_result > highest) {
            lane_result = highest;
            result.saturated = true;
        } else if (lane_result < lowest) {
            lane_result = lowest;
            result.saturated = true;
        }
        result.high |= (@bitCast(u64, @intCast(i64, lane_result)) & mask) << amount;
    }
    return result;
}

pub fn signedSaturatingDoublingProductPartsVector(left: a64_state.VectorValue, right: a64_state.VectorValue, full: bool, lane: u8) VectorSaturatingProductParts {
    const lower = signedSaturatingDoublingProductParts64(left.low, right.low, lane);
    const upper = if (full) signedSaturatingDoublingProductParts64(left.high, right.high, lane) else SaturatingProductParts{ .high = 0, .low = 0, .saturated = false };
    return VectorSaturatingProductParts{
        .high = a64_state.VectorValue{ .low = lower.high, .high = upper.high },
        .low = a64_state.VectorValue{ .low = lower.low, .high = upper.low },
        .saturated = lower.saturated or upper.saturated,
    };
}

pub fn signedSaturatingDoublingLongProductHalf(left: u64, right: u64, lane: u8) WideSaturatingVectorResult {
    const mask = ones(lane);
    const target_bits = lane * 2;
    const highest = (@as(i128, 1) << @intCast(u7, target_bits - 1)) - 1;
    const lowest = -(@as(i128, 1) << @intCast(u7, target_bits - 1));
    var result = WideSaturatingVectorResult{ .value = a64_state.VectorValue{ .low = 0, .high = 0 }, .saturated = false };
    var index: u8 = 0;
    while (index < 64 / lane) : (index += 1) {
        const source_shift = @intCast(u6, index * lane);
        const left_lane = @intCast(i128, @bitCast(i64, signExtendRuntime((left >> source_shift) & mask, @intCast(u6, lane))));
        const right_lane = @intCast(i128, @bitCast(i64, signExtendRuntime((right >> source_shift) & mask, @intCast(u6, lane))));
        var doubled = left_lane * right_lane * 2;
        if (doubled > highest) {
            doubled = highest;
            result.saturated = true;
        } else if (doubled < lowest) {
            doubled = lowest;
            result.saturated = true;
        }
        const output = @bitCast(u64, @intCast(i64, doubled));
        if (lane == 16) {
            const shift = @intCast(u6, index * 32);
            if (index < 2) {
                result.value.low |= (output & 0xffffffff) << shift;
            } else {
                result.value.high |= (output & 0xffffffff) << @intCast(u6, (index - 2) * 32);
            }
        } else if (index == 0) {
            result.value.low = output;
        } else {
            result.value.high = output;
        }
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

pub fn splitLaneProducts64(left: u64, right: u64, lane: u8, signed: bool) LaneProductParts {
    const mask = a64_logic_masks.ones(lane);
    var result = LaneProductParts{ .high = 0, .low = 0 };
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_raw = (left >> amount) & mask;
        const right_raw = (right >> amount) & mask;
        const product = if (signed) blk: {
            const left_signed = @intCast(i128, @bitCast(i64, a64_immediate_vectors.signExtendRuntime(left_raw, @intCast(u6, lane))));
            const right_signed = @intCast(i128, @bitCast(i64, a64_immediate_vectors.signExtendRuntime(right_raw, @intCast(u6, lane))));
            break :blk @bitCast(u128, left_signed * right_signed);
        } else @intCast(u128, left_raw) * @intCast(u128, right_raw);
        result.low |= @intCast(u64, product & @intCast(u128, mask)) << amount;
        result.high |= @intCast(u64, (product >> @intCast(u7, lane)) & @intCast(u128, mask)) << amount;
    }
    return result;
}

pub fn splitLaneProductsVector(left: a64_state.VectorValue, right: a64_state.VectorValue, full: bool, lane: u8, signed: bool) VectorProductParts {
    const lower = splitLaneProducts64(left.low, right.low, lane, signed);
    const upper = if (full) splitLaneProducts64(left.high, right.high, lane, signed) else LaneProductParts{ .high = 0, .low = 0 };
    return VectorProductParts{
        .high = a64_state.VectorValue{ .low = lower.high, .high = upper.high },
        .low = a64_state.VectorValue{ .low = lower.low, .high = upper.low },
    };
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
