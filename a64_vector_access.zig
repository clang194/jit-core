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

