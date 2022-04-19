const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub fn addFloatVector(control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, full: bool, left: a64_state.VectorValue, right: a64_state.VectorValue) a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        setVectorElement(&result, index, bytes, floatAdd(control, mode, double, vectorElement(left, index, bytes), vectorElement(right, index, bytes)));
    }
    return result;
}

pub fn subtractFloatVector(control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, full: bool, left: a64_state.VectorValue, right: a64_state.VectorValue) a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        setVectorElement(&result, index, bytes, floatSub(control, mode, double, vectorElement(left, index, bytes), vectorElement(right, index, bytes)));
    }
    return result;
}

pub fn divideFloatVector(control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, full: bool, left: a64_state.VectorValue, right: a64_state.VectorValue) a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        setVectorElement(&result, index, bytes, floatDiv(control, mode, double, vectorElement(left, index, bytes), vectorElement(right, index, bytes)));
    }
    return result;
}

pub fn multiplyFloatVector(control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, full: bool, left: a64_state.VectorValue, right: a64_state.VectorValue) a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        setVectorElement(&result, index, bytes, floatMul(control, mode, double, vectorElement(left, index, bytes), vectorElement(right, index, bytes)));
    }
    return result;
}

pub fn negateFloatVector(double: bool, full: bool, source: a64_state.VectorValue) a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        setVectorElement(&result, index, bytes, negateFloat(double, vectorElement(source, index, bytes)));
    }
    return result;
}

pub fn negateHalfFloatVector(full: bool, source: a64_state.VectorValue) a64_state.VectorValue {
    const lanes = if (full) @as(usize, 8) else @as(usize, 4);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        setVectorElement(&result, index, 2, vectorElement(source, index, 2) ^ 0x8000);
    }
    return result;
}

pub fn signedWordsToFloatVector(full: bool, source: a64_state.VectorValue) a64_state.VectorValue {
    const lanes = if (full) @as(usize, 4) else @as(usize, 2);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        setVectorElement(&result, index, 4, signedWordToFloat32(@intCast(u32, vectorElement(source, index, 4))));
    }
    return result;
}
