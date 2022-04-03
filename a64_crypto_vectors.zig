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

pub fn sm3SelectWord(addend: a64_state.VectorValue, message: a64_state.VectorValue, state: a64_state.VectorValue) a64_state.VectorValue {
    const top_addend = @intCast(u32, vectorElement(addend, 3, 4));
    const top_message = @intCast(u32, vectorElement(message, 3, 4));
    const top_state = @intCast(u32, vectorElement(state, 3, 4));
    const rotated_state = (top_state >> 20) | (top_state << 12);
    const sum = rotated_state +% top_message +% top_addend;
    const result = (sum >> 25) | (sum << 7);
    return a64_state.VectorValue{ .low = 0, .high = @as(u64, result) << 32 };
}

fn sm3MixOne(target: a64_state.VectorValue, message: a64_state.VectorValue, state: a64_state.VectorValue, index: usize, choose_majority: bool) a64_state.VectorValue {
    const low_target = @intCast(u32, vectorElement(target, 0, 4));
    const after_low_target = @intCast(u32, vectorElement(target, 1, 4));
    const before_top_target = @intCast(u32, vectorElement(target, 2, 4));
    const top_target = @intCast(u32, vectorElement(target, 3, 4));
    const top_state = @intCast(u32, vectorElement(state, 3, 4));
    const message_word = @intCast(u32, vectorElement(message, index, 4));
    const selected_state = top_state ^ ((top_target >> 20) | (top_target << 12));
    const combined_target = if (choose_majority)
        (top_target & after_low_target) | (top_target & before_top_target) | (after_low_target & before_top_target)
    else
        after_low_target ^ top_target ^ before_top_target;
    const top_result = combined_target +% low_target +% selected_state +% message_word;
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    setVectorElement(&result, 0, 4, after_low_target);
    setVectorElement(&result, 1, 4, (before_top_target >> 23) | (before_top_target << 9));
    setVectorElement(&result, 2, 4, top_target);
    setVectorElement(&result, 3, 4, top_result);
    return result;
}

pub fn sm3MixOneA(target: a64_state.VectorValue, message: a64_state.VectorValue, state: a64_state.VectorValue, index: usize) a64_state.VectorValue {
    return sm3MixOne(target, message, state, index, false);
}

pub fn sm3MixOneB(target: a64_state.VectorValue, message: a64_state.VectorValue, state: a64_state.VectorValue, index: usize) a64_state.VectorValue {
    return sm3MixOne(target, message, state, index, true);
}

pub fn sm3MixTwoA(target: a64_state.VectorValue, message: a64_state.VectorValue, state: a64_state.VectorValue, index: usize) a64_state.VectorValue {
    const low_target = @intCast(u32, vectorElement(target, 0, 4));
    const after_low_target = @intCast(u32, vectorElement(target, 1, 4));
    const before_top_target = @intCast(u32, vectorElement(target, 2, 4));
    const top_target = @intCast(u32, vectorElement(target, 3, 4));
    const top_state = @intCast(u32, vectorElement(state, 3, 4));
    const message_word = @intCast(u32, vectorElement(message, index, 4));
    const combined_target = after_low_target ^ top_target ^ before_top_target;
    const combined = combined_target +% low_target +% top_state +% message_word;
    const top_result = combined ^ ((combined >> 23) | (combined << 9)) ^ ((combined >> 15) | (combined << 17));
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    setVectorElement(&result, 0, 4, after_low_target);
    setVectorElement(&result, 1, 4, (before_top_target >> 13) | (before_top_target << 19));
    setVectorElement(&result, 2, 4, top_target);
    setVectorElement(&result, 3, 4, top_result);
    return result;
}
