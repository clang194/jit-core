const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub fn vectorByte(value: a64_state.VectorValue, index: usize) u8 {
    const shift = @intCast(u6, (index & 7) * 8);
    const word = if (index < 8) value.low else value.high;
    return @intCast(u8, (word >> shift) & 0xff);
}

pub fn vectorElement(value: a64_state.VectorValue, index: usize, bytes: usize) u64 {
    var result: u64 = 0;
    var byte_index: usize = 0;
    while (byte_index < bytes) : (byte_index += 1) {
        result |= @as(u64, vectorByte(value, index * bytes + byte_index)) << @intCast(u6, byte_index * 8);
    }
    return result;
}

pub fn setVectorByte(value: *a64_state.VectorValue, index: usize, byte: u8) void {
    const shift = @intCast(u6, (index & 7) * 8);
    const mask = @as(u64, 0xff) << shift;
    const shifted = @as(u64, byte) << shift;
    if (index < 8) {
        value.low = (value.low & ~mask) | shifted;
    } else {
        value.high = (value.high & ~mask) | shifted;
    }
}

pub fn setVectorElement(value: *a64_state.VectorValue, index: usize, bytes: usize, element: u64) void {
    var byte_index: usize = 0;
    while (byte_index < bytes) : (byte_index += 1) {
        const byte = @intCast(u8, (element >> @intCast(u6, byte_index * 8)) & 0xff);
        setVectorByte(value, index * bytes + byte_index, byte);
    }
}

pub fn interleaveLowerVector(left: a64_state.VectorValue, right: a64_state.VectorValue, bytes: usize, total: usize) a64_state.VectorValue {
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    const pairs = total / bytes / 2;
    var index: usize = 0;
    while (index < pairs) : (index += 1) {
        setVectorElement(&result, index * 2, bytes, vectorElement(left, index, bytes));
        setVectorElement(&result, index * 2 + 1, bytes, vectorElement(right, index, bytes));
    }
    return result;
}

pub fn interleaveUpperVector(left: a64_state.VectorValue, right: a64_state.VectorValue, bytes: usize, total: usize) a64_state.VectorValue {
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    const pairs = total / bytes / 2;
    var index: usize = 0;
    while (index < pairs) : (index += 1) {
        const source_index = index + pairs;
        setVectorElement(&result, index * 2, bytes, vectorElement(left, source_index, bytes));
        setVectorElement(&result, index * 2 + 1, bytes, vectorElement(right, source_index, bytes));
    }
    return result;
}

pub fn transposeLowerVector(left: a64_state.VectorValue, right: a64_state.VectorValue, bytes: usize, total: usize) a64_state.VectorValue {
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    const pairs = total / bytes / 2;
    var index: usize = 0;
    while (index < pairs) : (index += 1) {
        const source_index = index * 2;
        setVectorElement(&result, index * 2, bytes, vectorElement(left, source_index, bytes));
        setVectorElement(&result, index * 2 + 1, bytes, vectorElement(right, source_index, bytes));
    }
    return result;
}

pub fn transposeUpperVector(left: a64_state.VectorValue, right: a64_state.VectorValue, bytes: usize, total: usize) a64_state.VectorValue {
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    const pairs = total / bytes / 2;
    var index: usize = 0;
    while (index < pairs) : (index += 1) {
        const source_index = index * 2 + 1;
        setVectorElement(&result, index * 2, bytes, vectorElement(left, source_index, bytes));
        setVectorElement(&result, index * 2 + 1, bytes, vectorElement(right, source_index, bytes));
    }
    return result;
}

pub fn unzipLowerVector(left: a64_state.VectorValue, right: a64_state.VectorValue, bytes: usize, total: usize) a64_state.VectorValue {
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    const pairs = total / bytes / 2;
    var index: usize = 0;
    while (index < pairs) : (index += 1) {
        setVectorElement(&result, index, bytes, vectorElement(left, index * 2, bytes));
        setVectorElement(&result, index + pairs, bytes, vectorElement(right, index * 2, bytes));
    }
    return result;
}

pub fn unzipUpperVector(left: a64_state.VectorValue, right: a64_state.VectorValue, bytes: usize, total: usize) a64_state.VectorValue {
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    const pairs = total / bytes / 2;
    var index: usize = 0;
    while (index < pairs) : (index += 1) {
        setVectorElement(&result, index, bytes, vectorElement(left, index * 2 + 1, bytes));
        setVectorElement(&result, index + pairs, bytes, vectorElement(right, index * 2 + 1, bytes));
    }
    return result;
}

pub fn extractVectorBytes(left: a64_state.VectorValue, right: a64_state.VectorValue, start: usize, total: usize) a64_state.VectorValue {
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < total) : (index += 1) {
        const source_index = start + index;
        const byte = if (source_index < total) vectorByte(left, source_index) else vectorByte(right, source_index - total);
        setVectorByte(&result, index, byte);
    }
    return result;
}

pub fn pairwiseAddUnsignedWideVector(source: a64_state.VectorValue, source_bytes: usize, total: usize) a64_state.VectorValue {
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    const target_bytes = source_bytes * 2;
    const pairs = total / source_bytes / 2;
    var index: usize = 0;
    while (index < pairs) : (index += 1) {
        const left = vectorElement(source, index * 2, source_bytes);
        const right = vectorElement(source, index * 2 + 1, source_bytes);
        setVectorElement(&result, index, target_bytes, left + right);
    }
    return result;
}

pub fn narrowVectorLanes(value: a64_state.VectorValue, bytes: usize) u64 {
    var result: u64 = 0;
    const mask = ones(@intCast(u8, bytes * 8));
    var index: usize = 0;
    while (index < 8 / bytes) : (index += 1) {
        const element = vectorElement(value, index, bytes * 2) & mask;
        result |= element << @intCast(u6, index * bytes * 8);
    }
    return result;
}

pub fn narrowShiftRightVectorLanes(value: a64_state.VectorValue, bytes: usize, amount: u8) u64 {
    var result: u64 = 0;
    const mask = ones(@intCast(u8, bytes * 8));
    const source_bytes = bytes * 2;
    var index: usize = 0;
    while (index < 8 / bytes) : (index += 1) {
        const element = (vectorElement(value, index, source_bytes) >> @intCast(u6, amount)) & mask;
        result |= element << @intCast(u6, index * bytes * 8);
    }
    return result;
}

pub fn narrowRoundedShiftRightVectorLanes(value: a64_state.VectorValue, bytes: usize, amount: u8) u64 {
    var result: u64 = 0;
    const mask = ones(@intCast(u8, bytes * 8));
    const source_bytes = bytes * 2;
    const round = @as(u64, 1) << @intCast(u6, amount - 1);
    var index: usize = 0;
    while (index < 8 / bytes) : (index += 1) {
        const element = ((vectorElement(value, index, source_bytes) +% round) >> @intCast(u6, amount)) & mask;
        result |= element << @intCast(u6, index * bytes * 8);
    }
    return result;
}
