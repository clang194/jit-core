const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub fn equalVectorLanes(left: u64, right: u64, lane: u8) u64 {
    if (lane == 64) {
        return if (left == right) ~@as(u64, 0) else 0;
    }

    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        if (((left >> amount) & mask) == ((right >> amount) & mask)) {
            result |= mask << amount;
        }
    }
    return result;
}

pub fn sharedBitVectorLanes(left: u64, right: u64, lane: u8) u64 {
    if (lane == 64) {
        return if ((left & right) != 0) ~@as(u64, 0) else 0;
    }

    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        if ((((left >> amount) & (right >> amount)) & mask) != 0) {
            result |= mask << amount;
        }
    }
    return result;
}

pub fn greaterSignedVectorLanes(left: u64, right: u64, lane: u8, inclusive: bool) u64 {
    if (lane == 64) {
        const left_signed = @bitCast(i64, left);
        const right_signed = @bitCast(i64, right);
        return if (if (inclusive) left_signed >= right_signed else left_signed > right_signed) ~@as(u64, 0) else 0;
    }

    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_signed = @bitCast(i64, signExtendRuntime((left >> amount) & mask, @intCast(u6, lane)));
        const right_signed = @bitCast(i64, signExtendRuntime((right >> amount) & mask, @intCast(u6, lane)));
        if (if (inclusive) left_signed >= right_signed else left_signed > right_signed) {
            result |= mask << amount;
        }
    }
    return result;
}

pub fn greaterUnsignedVectorLanes(left: u64, right: u64, lane: u8, inclusive: bool) u64 {
    if (lane == 64) {
        return if (if (inclusive) left >= right else left > right) ~@as(u64, 0) else 0;
    }

    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_element = (left >> amount) & mask;
        const right_element = (right >> amount) & mask;
        if (if (inclusive) left_element >= right_element else left_element > right_element) {
            result |= mask << amount;
        }
    }
    return result;
}

pub fn compareZeroVectorLanes(value: u64, lane: u8, greater: bool, equal: bool, inclusive: bool) u64 {
    if (greater) {
        return greaterSignedVectorLanes(value, 0, lane, inclusive);
    }
    if (equal) {
        return equalVectorLanes(value, 0, lane);
    }
    return greaterSignedVectorLanes(0, value, lane, false);
}

pub fn minMaxVectorLanes(left: u64, right: u64, lane: u8, signed: bool, maximum: bool) u64 {
    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const left_element = (left >> amount) & mask;
        const right_element = (right >> amount) & mask;
        const take_left = if (signed) blk: {
            const left_signed = @bitCast(i64, signExtendRuntime(left_element, @intCast(u6, lane)));
            const right_signed = @bitCast(i64, signExtendRuntime(right_element, @intCast(u6, lane)));
            break :blk if (maximum) left_signed > right_signed else left_signed < right_signed;
        } else if (maximum) left_element > right_element else left_element < right_element;
        result |= (if (take_left) left_element else right_element) << amount;
    }
    return result;
}

pub fn pairVectorHalves(first: u64, second: u64, lane: u8) u64 {
    if (lane == 64) {
        return first +% second;
    }

    return pairVectorHalf(first, lane) | (pairVectorHalf(second, lane) << @intCast(u6, 32));
}

pub fn pairVectorHalf(value: u64, lane: u8) u64 {
    const mask = ones(lane);
    const lane_step = @intCast(u8, lane);
    var result: u64 = 0;
    var input_shift: u8 = 0;
    var output_shift: u8 = 0;
    while (input_shift < 64) {
        const first_shift = @intCast(u6, input_shift);
        const second_shift = @intCast(u6, input_shift + lane_step);
        const output_amount = @intCast(u6, output_shift);
        const sum = ((value >> first_shift) & mask) +% ((value >> second_shift) & mask);
        result |= (sum & mask) << output_amount;
        input_shift += lane_step * 2;
        output_shift += lane_step;
    }
    return result;
}
