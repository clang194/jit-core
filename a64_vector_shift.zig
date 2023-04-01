const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub const SaturatingShiftResult = struct {
    value: u64,
    saturated: bool,
};

pub fn repeatedShiftAmountVector(lane: u8, amount: u8) u64 {
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        result |= @as(u64, amount) << @intCast(u6, shift);
    }
    return result;
}

pub fn shiftLeftVectorLanes(value: u64, lane: u8, amount: u8) u64 {
    if (amount >= lane) {
        return 0;
    }
    if (lane == 64) {
        return value << @intCast(u6, amount);
    }

    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const element = (value >> position) & mask;
        result |= ((element << @intCast(u6, amount)) & mask) << position;
    }
    return result;
}

pub fn insertShiftLeftVectorLanes(target: u64, source: u64, lane: u8, amount: u8) u64 {
    const mask = ones(lane);
    const insert_mask = (mask << @intCast(u6, amount)) & mask;
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const target_element = (target >> position) & mask;
        const source_element = (source >> position) & mask;
        const inserted = (source_element << @intCast(u6, amount)) & mask;
        result |= ((target_element & ~insert_mask) | inserted) << position;
    }
    return result;
}

pub fn shiftRightVectorLanes(value: u64, lane: u8, amount: u8) u64 {
    if (amount >= lane) {
        return 0;
    }
    if (lane == 64) {
        return value >> @intCast(u6, amount);
    }

    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const element = (value >> position) & mask;
        result |= (element >> @intCast(u6, amount)) << position;
    }
    return result;
}

pub fn insertShiftRightVectorLanes(target: u64, source: u64, lane: u8, amount: u8) u64 {
    const mask = ones(lane);
    const insert_mask = if (amount >= lane) @as(u64, 0) else mask >> @intCast(u6, amount);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const target_element = (target >> position) & mask;
        const source_element = (source >> position) & mask;
        const inserted = if (amount >= lane) @as(u64, 0) else source_element >> @intCast(u6, amount);
        result |= ((target_element & ~insert_mask) | inserted) << position;
    }
    return result;
}

pub fn roundedShiftRightVectorLanes(value: u64, lane: u8, amount: u8) u64 {
    const mask = ones(lane);
    const round = @as(u64, 1) << @intCast(u6, amount - 1);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const element = (value >> position) & mask;
        const shifted = if (amount >= lane) @as(u64, 0) else element >> @intCast(u6, amount);
        const corrected = shifted +% if ((element & round) != 0) @as(u64, 1) else @as(u64, 0);
        result |= (corrected & mask) << position;
    }
    return result;
}

pub fn shiftRightSignedVectorLanes(value: u64, lane: u8, amount: u8) u64 {
    const mask = ones(lane);
    const sign = @as(u64, 1) << @intCast(u6, lane - 1);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const element = (value >> position) & mask;
        const shifted = if ((element & sign) == 0)
            if (amount >= lane) @as(u64, 0) else element >> @intCast(u6, amount)
        else if (amount >= lane) mask else (element >> @intCast(u6, amount)) | (mask ^ (mask >> @intCast(u6, amount)));
        result |= shifted << position;
    }
    return result;
}

pub fn roundedShiftRightSignedVectorLanes(value: u64, lane: u8, amount: u8) u64 {
    const mask = ones(lane);
    const round = @as(u64, 1) << @intCast(u6, amount - 1);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const element = (value >> position) & mask;
        const shifted = shiftRightSignedVectorLanes(element, lane, amount) & mask;
        const corrected = shifted +% if ((element & round) != 0) @as(u64, 1) else @as(u64, 0);
        result |= (corrected & mask) << position;
    }
    return result;
}

pub fn variableUnsignedShiftVectorLanes(value: u64, shifts: u64, lane: u8) u64 {
    const mask = ones(lane);
    const limit = @as(i16, lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const element = (value >> position) & mask;
        const amount = @as(i16, @bitCast(i8, @intCast(u8, (shifts >> position) & 0xff)));
        const shifted = if (amount <= -limit or amount >= limit)
            @as(u64, 0)
        else if (amount < 0)
            element >> @intCast(u6, -amount)
        else
            (element << @intCast(u6, amount)) & mask;
        result |= shifted << position;
    }
    return result;
}

pub fn variableSignedShiftVectorLanes(value: u64, shifts: u64, lane: u8) u64 {
    const mask = ones(lane);
    const sign = @as(u64, 1) << @intCast(u6, lane - 1);
    const limit = @as(i16, lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const element = (value >> position) & mask;
        const amount = @as(i16, @bitCast(i8, @intCast(u8, (shifts >> position) & 0xff)));
        const shifted = if (amount >= limit)
            @as(u64, 0)
        else if (amount <= -limit)
            if ((element & sign) == 0) @as(u64, 0) else mask
        else if (amount < 0)
            shiftRightSignedVectorLanes(element, lane, @intCast(u8, -amount)) & mask
        else
            (element << @intCast(u6, amount)) & mask;
        result |= shifted << position;
    }
    return result;
}

pub fn variableSignedSaturatingShiftLeftVectorLanes(value: u64, shifts: u64, lane: u8) SaturatingShiftResult {
    const mask = ones(lane);
    const sign = @as(u64, 1) << @intCast(u6, lane - 1);
    const highest = sign - 1;
    const lowest = sign;
    const limit = @as(i16, lane - 1);
    var result = SaturatingShiftResult{ .value = 0, .saturated = false };
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const element = (value >> position) & mask;
        const amount = @as(i16, @bitCast(i8, @intCast(u8, (shifts >> position) & 0xff)));
        const shifted = if (element == 0)
            @as(u64, 0)
        else if (amount < 0) blk: {
            const right = if (amount < -limit) limit else -amount;
            break :blk signedElementRightShift(element, lane, @intCast(u8, right)) & mask;
        } else if (amount > limit) blk: {
            result.saturated = true;
            break :blk if ((element & sign) == 0) highest else lowest;
        } else blk: {
            const widened = @as(u128, element) << @intCast(u7, amount);
            const shifted_element = @intCast(u64, widened & @intCast(u128, mask));
            if ((signedElementRightShift(shifted_element, lane, @intCast(u8, amount)) & mask) != element) {
                result.saturated = true;
                break :blk if ((element & sign) == 0) highest else lowest;
            }
            break :blk shifted_element;
        };
        result.value |= shifted << position;
    }
    return result;
}

pub fn variableUnsignedSaturatingShiftLeftVectorLanes(value: u64, shifts: u64, lane: u8) SaturatingShiftResult {
    const mask = ones(lane);
    const limit = @as(i16, lane);
    var result = SaturatingShiftResult{ .value = 0, .saturated = false };
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const element = (value >> position) & mask;
        const amount = @as(i16, @bitCast(i8, @intCast(u8, (shifts >> position) & 0xff)));
        const shifted = if (element == 0 or amount <= -limit)
            @as(u64, 0)
        else if (amount < 0)
            element >> @intCast(u6, -amount)
        else if (amount >= limit) blk: {
            result.saturated = true;
            break :blk mask;
        } else blk: {
            const shifted_element = (element << @intCast(u6, amount)) & mask;
            if ((shifted_element >> @intCast(u6, amount)) != element) {
                result.saturated = true;
                break :blk mask;
            }
            break :blk shifted_element;
        };
        result.value |= shifted << position;
    }
    return result;
}

pub fn variableSignedUnsignedSaturatingShiftLeftVectorLanes(value: u64, shifts: u64, lane: u8) SaturatingShiftResult {
    const mask = ones(lane);
    const sign = @as(u64, 1) << @intCast(u6, lane - 1);
    const limit = @as(i16, lane - 1);
    var result = SaturatingShiftResult{ .value = 0, .saturated = false };
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const element = (value >> position) & mask;
        const amount = @as(i16, @bitCast(i8, @intCast(u8, (shifts >> position) & 0xff)));
        const shifted = if (element == 0)
            @as(u64, 0)
        else if ((element & sign) != 0) blk: {
            result.saturated = true;
            break :blk @as(u64, 0);
        } else if (amount < 0) blk: {
            const right = if (amount < -limit) limit else -amount;
            break :blk element >> @intCast(u6, right);
        } else if (amount > limit) blk: {
            result.saturated = true;
            break :blk mask;
        } else blk: {
            const shifted_element = (element << @intCast(u6, amount)) & mask;
            if ((shifted_element >> @intCast(u6, amount)) != element) {
                result.saturated = true;
                break :blk mask;
            }
            break :blk shifted_element;
        };
        result.value |= shifted << position;
    }
    return result;
}

fn signedElementRightShift(element: u64, lane: u8, amount: u8) u64 {
    const mask = ones(lane);
    const sign = @as(u64, 1) << @intCast(u6, lane - 1);
    if ((element & sign) == 0) {
        return element >> @intCast(u6, amount);
    }
    return (element >> @intCast(u6, amount)) | (mask ^ (mask >> @intCast(u6, amount)));
}

pub fn variableRoundedUnsignedShiftVectorLanes(value: u64, shifts: u64, lane: u8) u64 {
    const mask = ones(lane);
    const limit = @as(i16, lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const element = (value >> position) & mask;
        const amount = @as(i16, @bitCast(i8, @intCast(u8, (shifts >> position) & 0xff)));
        const shifted = if (amount >= limit or amount < -limit)
            @as(u64, 0)
        else if (amount < 0) blk: {
            const round = (element >> @intCast(u6, -amount - 1)) & 1;
            if (amount == -limit) {
                break :blk round;
            }
            break :blk ((element >> @intCast(u6, -amount)) +% round) & mask;
        } else (element << @intCast(u6, amount)) & mask;
        result |= shifted << position;
    }
    return result;
}

pub fn variableRoundedSignedShiftVectorLanes(value: u64, shifts: u64, lane: u8) u64 {
    const mask = ones(lane);
    const limit = @as(i16, lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const position = @intCast(u6, shift);
        const element = (value >> position) & mask;
        const amount = @as(i16, @bitCast(i8, @intCast(u8, (shifts >> position) & 0xff)));
        const shifted = if (amount >= limit or amount <= -limit)
            @as(u64, 0)
        else if (amount < 0) blk: {
            const round = (element >> @intCast(u6, -amount - 1)) & 1;
            break :blk (signedElementRightShift(element, lane, @intCast(u8, -amount)) +% round) & mask;
        } else (element << @intCast(u6, amount)) & mask;
        result |= shifted << position;
    }
    return result;
}

pub fn widenShiftLeftVectorHalf(value: u64, lane: u8, amount: u6) a64_state.VectorValue {
    const output_lane = lane * 2;
    const input_mask = ones(lane);
    const output_mask = ones(output_lane);
    const output_bytes = @intCast(usize, output_lane / 8);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < 64 / @as(usize, lane)) : (index += 1) {
        const input_shift = @intCast(u6, index * @as(usize, lane));
        const element = (value >> input_shift) & input_mask;
        setVectorElement(&result, index, output_bytes, (element << amount) & output_mask);
    }
    return result;
}

pub fn widenSignedShiftLeftVectorHalf(value: u64, lane: u8, amount: u6) a64_state.VectorValue {
    const output_lane = lane * 2;
    const input_mask = ones(lane);
    const output_mask = ones(output_lane);
    const output_bytes = @intCast(usize, output_lane / 8);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < 64 / @as(usize, lane)) : (index += 1) {
        const input_shift = @intCast(u6, index * @as(usize, lane));
        const element = signExtendRuntime((value >> input_shift) & input_mask, @intCast(u6, lane));
        setVectorElement(&result, index, output_bytes, (element << amount) & output_mask);
    }
    return result;
}
