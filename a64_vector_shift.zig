const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

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
