const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub fn aesDouble(value: u8) u8 {
    const shifted = (@as(u16, value) << 1) & 0xff;
    const reduced = if ((value & 0x80) != 0) shifted ^ 0x1b else shifted;
    return @intCast(u8, reduced);
}

pub fn aesProduct(value: u8, factor: u8) u8 {
    var left = value;
    var right = factor;
    var result: u8 = 0;
    while (right != 0) : (right >>= 1) {
        if ((right & 1) != 0) {
            result ^= left;
        }
        left = aesDouble(left);
    }
    return result;
}

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

pub fn encryptAesVector(input: a64_state.VectorValue) a64_state.VectorValue {
    var shifted = a64_state.VectorValue{ .low = 0, .high = 0 };
    setVectorByte(&shifted, 0, vectorByte(input, 0));
    setVectorByte(&shifted, 4, vectorByte(input, 4));
    setVectorByte(&shifted, 8, vectorByte(input, 8));
    setVectorByte(&shifted, 12, vectorByte(input, 12));
    setVectorByte(&shifted, 1, vectorByte(input, 5));
    setVectorByte(&shifted, 5, vectorByte(input, 9));
    setVectorByte(&shifted, 9, vectorByte(input, 13));
    setVectorByte(&shifted, 13, vectorByte(input, 1));
    setVectorByte(&shifted, 2, vectorByte(input, 10));
    setVectorByte(&shifted, 10, vectorByte(input, 2));
    setVectorByte(&shifted, 6, vectorByte(input, 14));
    setVectorByte(&shifted, 14, vectorByte(input, 6));
    setVectorByte(&shifted, 3, vectorByte(input, 15));
    setVectorByte(&shifted, 15, vectorByte(input, 11));
    setVectorByte(&shifted, 11, vectorByte(input, 7));
    setVectorByte(&shifted, 7, vectorByte(input, 3));

    var output = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < 16) : (index += 1) {
        setVectorByte(&output, index, aesForwardBox[vectorByte(shifted, index)]);
    }
    return output;
}

pub fn decryptAesVector(input: a64_state.VectorValue) a64_state.VectorValue {
    var shifted = a64_state.VectorValue{ .low = 0, .high = 0 };
    setVectorByte(&shifted, 0, vectorByte(input, 0));
    setVectorByte(&shifted, 4, vectorByte(input, 4));
    setVectorByte(&shifted, 8, vectorByte(input, 8));
    setVectorByte(&shifted, 12, vectorByte(input, 12));
    setVectorByte(&shifted, 1, vectorByte(input, 13));
    setVectorByte(&shifted, 5, vectorByte(input, 1));
    setVectorByte(&shifted, 9, vectorByte(input, 5));
    setVectorByte(&shifted, 13, vectorByte(input, 9));
    setVectorByte(&shifted, 2, vectorByte(input, 10));
    setVectorByte(&shifted, 10, vectorByte(input, 2));
    setVectorByte(&shifted, 6, vectorByte(input, 14));
    setVectorByte(&shifted, 14, vectorByte(input, 6));
    setVectorByte(&shifted, 3, vectorByte(input, 7));
    setVectorByte(&shifted, 7, vectorByte(input, 11));
    setVectorByte(&shifted, 11, vectorByte(input, 15));
    setVectorByte(&shifted, 15, vectorByte(input, 3));

    var output = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < 16) : (index += 1) {
        setVectorByte(&output, index, aesReverseBox[vectorByte(shifted, index)]);
    }
    return output;
}

pub fn mixAesVector(input: a64_state.VectorValue, inverse: bool) a64_state.VectorValue {
    var output = a64_state.VectorValue{ .low = 0, .high = 0 };
    var column: usize = 0;
    while (column < 16) : (column += 4) {
        const a = vectorByte(input, column);
        const b = vectorByte(input, column + 1);
        const c = vectorByte(input, column + 2);
        const d = vectorByte(input, column + 3);
        if (inverse) {
            setVectorByte(&output, column, aesProduct(a, 0x0e) ^ aesProduct(b, 0x0b) ^ aesProduct(c, 0x0d) ^ aesProduct(d, 0x09));
            setVectorByte(&output, column + 1, aesProduct(a, 0x09) ^ aesProduct(b, 0x0e) ^ aesProduct(c, 0x0b) ^ aesProduct(d, 0x0d));
            setVectorByte(&output, column + 2, aesProduct(a, 0x0d) ^ aesProduct(b, 0x09) ^ aesProduct(c, 0x0e) ^ aesProduct(d, 0x0b));
            setVectorByte(&output, column + 3, aesProduct(a, 0x0b) ^ aesProduct(b, 0x0d) ^ aesProduct(c, 0x09) ^ aesProduct(d, 0x0e));
        } else {
            const fold = a ^ b ^ c ^ d;
            setVectorByte(&output, column, a ^ aesDouble(a ^ b) ^ fold);
            setVectorByte(&output, column + 1, b ^ aesDouble(b ^ c) ^ fold);
            setVectorByte(&output, column + 2, c ^ aesDouble(c ^ d) ^ fold);
            setVectorByte(&output, column + 3, d ^ aesDouble(d ^ a) ^ fold);
        }
    }
    return output;
}

pub fn xorRotatedDoublewordVector(left: a64_state.VectorValue, right: a64_state.VectorValue) a64_state.VectorValue {
    return a64_state.VectorValue{
        .low = left.low ^ ((right.low << 1) | (right.low >> 63)),
        .high = left.high ^ ((right.high << 1) | (right.high >> 63)),
    };
}
