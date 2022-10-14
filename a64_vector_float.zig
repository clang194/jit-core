const a64_state = @import("a64_state.zig");
const a64_float_minmax = @import("a64_float_minmax.zig");
const bits = @import("bits.zig");
const float_control = @import("float_control.zig");
const float_estimate = @import("float_estimate.zig");
const float_exception = @import("float_exception.zig");
const float_fused = @import("float_fused.zig");
const float_refine = @import("float_refine.zig");
const float_status = @import("float_status.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub const FloatZeroComparison = enum {
    equal,
    greater,
    greater_equal,
    less,
    less_equal,
};

pub const FloatComparison = enum {
    equal,
    greater,
    greater_equal,
};

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

pub fn addFloatPairsVector(control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, full: bool, left: a64_state.VectorValue, right: a64_state.VectorValue) a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const pairs = if (double) @as(usize, 1) else if (full) @as(usize, 2) else @as(usize, 1);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < pairs) : (index += 1) {
        setVectorElement(&result, index, bytes, floatAdd(control, mode, double, vectorElement(left, index * 2, bytes), vectorElement(left, index * 2 + 1, bytes)));
    }
    index = 0;
    while (index < pairs) : (index += 1) {
        setVectorElement(&result, index + pairs, bytes, floatAdd(control, mode, double, vectorElement(right, index * 2, bytes), vectorElement(right, index * 2 + 1, bytes)));
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

pub fn fusedMultiplyAddFloatVector(control: float_control.Control, status: *float_status.FloatStatus, double: bool, full: bool, addend: a64_state.VectorValue, left: a64_state.VectorValue, right: a64_state.VectorValue) float_exception.FloatExceptionError!a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        const value = if (double)
            try float_fused.mulAdd64(vectorElement(addend, index, bytes), vectorElement(left, index, bytes), vectorElement(right, index, bytes), control, status)
        else
            @as(u64, try float_fused.mulAdd32(@intCast(u32, vectorElement(addend, index, bytes)), @intCast(u32, vectorElement(left, index, bytes)), @intCast(u32, vectorElement(right, index, bytes)), control, status));
        setVectorElement(&result, index, bytes, value);
    }
    return result;
}

pub fn reciprocalEstimateFloatVector(control: float_control.Control, status: *float_status.FloatStatus, double: bool, full: bool, source: a64_state.VectorValue) float_exception.FloatExceptionError!a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        const value = vectorElement(source, index, bytes);
        const estimate = if (double)
            try float_estimate.reciprocalEstimate64(value, control, status)
        else
            @as(u64, try float_estimate.reciprocalEstimate32(@intCast(u32, value), control, status));
        setVectorElement(&result, index, bytes, estimate);
    }
    return result;
}

pub fn reciprocalStepFloatVector(control: float_control.Control, status: *float_status.FloatStatus, double: bool, full: bool, left: a64_state.VectorValue, right: a64_state.VectorValue) float_exception.FloatExceptionError!a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        const left_value = vectorElement(left, index, bytes);
        const right_value = vectorElement(right, index, bytes);
        const step = if (double)
            try float_refine.reciprocalStep64(left_value, right_value, control, status)
        else
            @as(u64, try float_refine.reciprocalStep32(@intCast(u32, left_value), @intCast(u32, right_value), control, status));
        setVectorElement(&result, index, bytes, step);
    }
    return result;
}

pub fn maximumFloatVector(control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, full: bool, left: a64_state.VectorValue, right: a64_state.VectorValue) a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        setVectorElement(&result, index, bytes, a64_float_minmax.floatMax(control, mode, double, vectorElement(left, index, bytes), vectorElement(right, index, bytes)));
    }
    return result;
}

pub fn minimumFloatVector(control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, full: bool, left: a64_state.VectorValue, right: a64_state.VectorValue) a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        setVectorElement(&result, index, bytes, a64_float_minmax.floatMin(control, mode, double, vectorElement(left, index, bytes), vectorElement(right, index, bytes)));
    }
    return result;
}

pub fn absoluteDifferenceFloatVector(control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, full: bool, left: a64_state.VectorValue, right: a64_state.VectorValue) a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    const mask = if (double) @as(u64, 0x7fffffffffffffff) else @as(u64, 0x7fffffff);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        const difference = floatSub(control, mode, double, vectorElement(left, index, bytes), vectorElement(right, index, bytes));
        setVectorElement(&result, index, bytes, difference & mask);
    }
    return result;
}

pub fn equalFloatVector(control: a64_state.FloatControl, double: bool, full: bool, left: a64_state.VectorValue, right: a64_state.VectorValue) a64_state.VectorValue {
    return compareFloatVector(control, double, full, left, right, .equal);
}

pub fn compareFloatVector(control: a64_state.FloatControl, double: bool, full: bool, left: a64_state.VectorValue, right: a64_state.VectorValue, comparison: FloatComparison) a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    const match_value = if (double) ~@as(u64, 0) else @as(u64, 0xffffffff);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        const matched = if (double) blk: {
            const left_input = floatInput64(control, vectorElement(left, index, bytes));
            const right_input = floatInput64(control, vectorElement(right, index, bytes));
            const left_value = @bitCast(f64, left_input);
            const right_value = @bitCast(f64, right_input);
            break :blk !isNan64(left_input) and !isNan64(right_input) and switch (comparison) {
                .equal => left_value == right_value,
                .greater => left_value > right_value,
                .greater_equal => left_value >= right_value,
            };
        } else blk: {
            const left_input = floatInput32(control, @intCast(u32, vectorElement(left, index, bytes)));
            const right_input = floatInput32(control, @intCast(u32, vectorElement(right, index, bytes)));
            const left_value = @bitCast(f32, left_input);
            const right_value = @bitCast(f32, right_input);
            break :blk !isNan32(left_input) and !isNan32(right_input) and switch (comparison) {
                .equal => left_value == right_value,
                .greater => left_value > right_value,
                .greater_equal => left_value >= right_value,
            };
        };
        setVectorElement(&result, index, bytes, if (matched) match_value else 0);
    }
    return result;
}

pub fn compareFloatZeroVector(control: a64_state.FloatControl, double: bool, full: bool, source: a64_state.VectorValue, comparison: FloatZeroComparison) a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    const match_value = if (double) ~@as(u64, 0) else @as(u64, 0xffffffff);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        const matched = if (double) blk: {
            const input = floatInput64(control, vectorElement(source, index, bytes));
            const value = @bitCast(f64, input);
            break :blk !isNan64(input) and switch (comparison) {
                .equal => value == 0.0,
                .greater => value > 0.0,
                .greater_equal => value >= 0.0,
                .less => value < 0.0,
                .less_equal => value <= 0.0,
            };
        } else blk: {
            const input = floatInput32(control, @intCast(u32, vectorElement(source, index, bytes)));
            const value = @bitCast(f32, input);
            break :blk !isNan32(input) and switch (comparison) {
                .equal => value == 0.0,
                .greater => value > 0.0,
                .greater_equal => value >= 0.0,
                .less => value < 0.0,
                .less_equal => value <= 0.0,
            };
        };
        setVectorElement(&result, index, bytes, if (matched) match_value else 0);
    }
    return result;
}

pub fn compareFloatZeroScalar(control: a64_state.FloatControl, double: bool, source: u64, comparison: FloatZeroComparison) u64 {
    const match_value = if (double) ~@as(u64, 0) else @as(u64, 0xffffffff);
    const matched = if (double) blk: {
        const input = floatInput64(control, source);
        const value = @bitCast(f64, input);
        break :blk !isNan64(input) and switch (comparison) {
            .equal => value == 0.0,
            .greater => value > 0.0,
            .greater_equal => value >= 0.0,
            .less => value < 0.0,
            .less_equal => value <= 0.0,
        };
    } else blk: {
        const input = floatInput32(control, @intCast(u32, source));
        const value = @bitCast(f32, input);
        break :blk !isNan32(input) and switch (comparison) {
            .equal => value == 0.0,
            .greater => value > 0.0,
            .greater_equal => value >= 0.0,
            .less => value < 0.0,
            .less_equal => value <= 0.0,
        };
    };
    return if (matched) match_value else 0;
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

pub fn absoluteFloatVector(double: bool, full: bool, source: a64_state.VectorValue) a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
    const mask = if (double) @as(u64, 0x7fffffffffffffff) else @as(u64, 0x7fffffff);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        setVectorElement(&result, index, bytes, vectorElement(source, index, bytes) & mask);
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

pub fn absoluteHalfFloatVector(full: bool, source: a64_state.VectorValue) a64_state.VectorValue {
    const lanes = if (full) @as(usize, 8) else @as(usize, 4);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        setVectorElement(&result, index, 2, vectorElement(source, index, 2) & 0x7fff);
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

pub fn signedDoublewordsToFloatVector(source: a64_state.VectorValue) a64_state.VectorValue {
    return a64_state.VectorValue{
        .low = signedDoublewordToFloat64(source.low),
        .high = signedDoublewordToFloat64(source.high),
    };
}

pub fn unsignedWordsToFloatVector(full: bool, source: a64_state.VectorValue) a64_state.VectorValue {
    const lanes = if (full) @as(usize, 4) else @as(usize, 2);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < lanes) : (index += 1) {
        setVectorElement(&result, index, 4, unsignedWordToFloat32(@intCast(u32, vectorElement(source, index, 4))));
    }
    return result;
}

pub fn unsignedDoublewordsToFloatVector(control: a64_state.FloatControl, source: a64_state.VectorValue) a64_state.VectorValue {
    return a64_state.VectorValue{
        .low = unsignedDoublewordToFloat64(control, source.low),
        .high = unsignedDoublewordToFloat64(control, source.high),
    };
}
