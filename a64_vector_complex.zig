const a64_state = @import("a64_state.zig");
const float_control = @import("float_control.zig");
const float_exception = @import("float_exception.zig");
const float_fused = @import("float_fused.zig");
const float_status = @import("float_status.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;
const a64_float_arithmetic = @import("a64_float_arithmetic.zig");
const floatAdd = a64_float_arithmetic.floatAdd;
const a64_float_minmax = @import("a64_float_minmax.zig");
const negateFloat = a64_float_minmax.negateFloat;
const a64_vector_access = @import("a64_vector_access.zig");
const setVectorElement = a64_vector_access.setVectorElement;
const vectorElement = a64_vector_access.vectorElement;

pub fn addComplexFloatVector(control: a64_state.FloatControl, mode: FloatNanMode64, double: bool, full: bool, left: a64_state.VectorValue, right: a64_state.VectorValue, rotated: bool) a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const pairs = if (double) @as(usize, 1) else if (full) @as(usize, 2) else @as(usize, 1);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < pairs) : (index += 1) {
        const first = index * 2;
        const second = first + 1;
        const right_first = vectorElement(right, first, bytes);
        const right_second = vectorElement(right, second, bytes);
        const add_first = if (rotated) right_second else negateFloat(double, right_second);
        const add_second = if (rotated) negateFloat(double, right_first) else right_first;
        setVectorElement(&result, first, bytes, floatAdd(control, mode, double, vectorElement(left, first, bytes), add_first));
        setVectorElement(&result, second, bytes, floatAdd(control, mode, double, vectorElement(left, second, bytes), add_second));
    }
    return result;
}

fn complexMultiplyInputs(double: bool, left: a64_state.VectorValue, right: a64_state.VectorValue, first: usize, second: usize, bytes: usize, rotation: u2, upper: bool) [2]u64 {
    const left_first = vectorElement(left, first, bytes);
    const left_second = vectorElement(left, second, bytes);
    const right_first = vectorElement(right, first, bytes);
    const right_second = vectorElement(right, second, bytes);
    return switch (rotation) {
        0 => if (upper) [2]u64{ left_first, right_second } else [2]u64{ left_first, right_first },
        1 => if (upper) [2]u64{ left_second, right_first } else [2]u64{ left_second, negateFloat(double, right_second) },
        2 => if (upper) [2]u64{ left_first, negateFloat(double, right_second) } else [2]u64{ left_first, negateFloat(double, right_first) },
        else => if (upper) [2]u64{ left_second, negateFloat(double, right_first) } else [2]u64{ left_second, right_second },
    };
}

fn complexMultiplyIndexedInputs(double: bool, left: a64_state.VectorValue, right: a64_state.VectorValue, first: usize, second: usize, bytes: usize, pair_index: usize, rotation: u2, upper: bool) [2]u64 {
    const left_first = vectorElement(left, first, bytes);
    const left_second = vectorElement(left, second, bytes);
    const right_first = vectorElement(right, pair_index * 2, bytes);
    const right_second = vectorElement(right, pair_index * 2 + 1, bytes);
    return switch (rotation) {
        0 => if (upper) [2]u64{ left_first, right_second } else [2]u64{ left_first, right_first },
        1 => if (upper) [2]u64{ left_second, right_first } else [2]u64{ left_second, negateFloat(double, right_second) },
        2 => if (upper) [2]u64{ left_first, negateFloat(double, right_second) } else [2]u64{ left_first, negateFloat(double, right_first) },
        else => if (upper) [2]u64{ left_second, negateFloat(double, right_first) } else [2]u64{ left_second, right_second },
    };
}

pub fn multiplyAddComplexFloatVector(control: float_control.Control, status: *float_status.FloatStatus, double: bool, full: bool, addend: a64_state.VectorValue, left: a64_state.VectorValue, right: a64_state.VectorValue, rotation: u2) float_exception.FloatExceptionError!a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const pairs = if (double) @as(usize, 1) else if (full) @as(usize, 2) else @as(usize, 1);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < pairs) : (index += 1) {
        const first = index * 2;
        const second = first + 1;
        const low_inputs = complexMultiplyInputs(double, left, right, first, second, bytes, rotation, false);
        const high_inputs = complexMultiplyInputs(double, left, right, first, second, bytes, rotation, true);
        const low_value = if (double)
            try float_fused.mulAdd64(vectorElement(addend, first, bytes), low_inputs[0], low_inputs[1], control, status)
        else
            @as(u64, try float_fused.mulAdd32(@intCast(u32, vectorElement(addend, first, bytes)), @intCast(u32, low_inputs[0]), @intCast(u32, low_inputs[1]), control, status));
        const high_value = if (double)
            try float_fused.mulAdd64(vectorElement(addend, second, bytes), high_inputs[0], high_inputs[1], control, status)
        else
            @as(u64, try float_fused.mulAdd32(@intCast(u32, vectorElement(addend, second, bytes)), @intCast(u32, high_inputs[0]), @intCast(u32, high_inputs[1]), control, status));
        setVectorElement(&result, first, bytes, low_value);
        setVectorElement(&result, second, bytes, high_value);
    }
    return result;
}

pub fn multiplyAddComplexFloatVectorByElement(control: float_control.Control, status: *float_status.FloatStatus, double: bool, full: bool, addend: a64_state.VectorValue, left: a64_state.VectorValue, right: a64_state.VectorValue, pair_index: usize, rotation: u2) float_exception.FloatExceptionError!a64_state.VectorValue {
    const bytes = if (double) @as(usize, 8) else @as(usize, 4);
    const pairs = if (double) @as(usize, 1) else if (full) @as(usize, 2) else @as(usize, 1);
    var result = a64_state.VectorValue{ .low = 0, .high = 0 };
    var index: usize = 0;
    while (index < pairs) : (index += 1) {
        const first = index * 2;
        const second = first + 1;
        const low_inputs = complexMultiplyIndexedInputs(double, left, right, first, second, bytes, pair_index, rotation, false);
        const high_inputs = complexMultiplyIndexedInputs(double, left, right, first, second, bytes, pair_index, rotation, true);
        const low_value = if (double)
            try float_fused.mulAdd64(vectorElement(addend, first, bytes), low_inputs[0], low_inputs[1], control, status)
        else
            @as(u64, try float_fused.mulAdd32(@intCast(u32, vectorElement(addend, first, bytes)), @intCast(u32, low_inputs[0]), @intCast(u32, low_inputs[1]), control, status));
        const high_value = if (double)
            try float_fused.mulAdd64(vectorElement(addend, second, bytes), high_inputs[0], high_inputs[1], control, status)
        else
            @as(u64, try float_fused.mulAdd32(@intCast(u32, vectorElement(addend, second, bytes)), @intCast(u32, high_inputs[0]), @intCast(u32, high_inputs[1]), control, status));
        setVectorElement(&result, first, bytes, low_value);
        setVectorElement(&result, second, bytes, high_value);
    }
    return result;
}
