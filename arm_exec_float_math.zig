const arm_state = @import("arm_state.zig");
const arm_types = @import("arm_exec_types.zig");
const ArmStepError = arm_types.ArmStepError;
const AddResult = arm_types.AddResult;
const CoprocessorOp = arm_types.CoprocessorOp;
const DataOp = arm_types.DataOp;
const DualMultiplyOp = arm_types.DualMultiplyOp;
const ExtendOp = arm_types.ExtendOp;
const FloatBinaryOp = arm_types.FloatBinaryOp;
const FloatUnaryOp = arm_types.FloatUnaryOp;
const FloatVectorPlan = arm_types.FloatVectorPlan;
const HalfMultiplyOp = arm_types.HalfMultiplyOp;
const MultiplyOp = arm_types.MultiplyOp;
const SaturatingWordResult = arm_types.SaturatingWordResult;
const ShiftMode = arm_types.ShiftMode;
const ShiftResult = arm_types.ShiftResult;
const bits = @import("bits.zig");
usingnamespace @import("arm_exec_types.zig");
usingnamespace @import("arm_exec_fetch_decode.zig");
usingnamespace @import("arm_exec_dispatch.zig");
usingnamespace @import("arm_exec_coprocessor.zig");
usingnamespace @import("arm_exec_float_decode.zig");
usingnamespace @import("arm_exec_float_run.zig");
usingnamespace @import("arm_exec_multiply_run.zig");
usingnamespace @import("arm_exec_status_branch.zig");
usingnamespace @import("arm_exec_data_transfer.zig");
usingnamespace @import("arm_exec_saturate_scalar.zig");
usingnamespace @import("arm_exec_parallel_saturate.zig");
usingnamespace @import("arm_exec_parallel_halve.zig");
usingnamespace @import("arm_exec_parallel_wrap.zig");
usingnamespace @import("arm_exec_memory_run.zig");
usingnamespace @import("arm_exec_transfer_checks.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
usingnamespace @import("arm_exec_immediate_run.zig");
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");

pub fn addFloat32(state: *arm_state.MachineState, left: u32, right: u32) u32 {
    const left_word = floatInput32(state, left);
    const right_word = floatInput32(state, right);
    var result = @bitCast(u32, @bitCast(f32, left_word) + @bitCast(f32, right_word));
    result = floatOutput32(state, result);
    if (state.floatDefaultNaN() and isNan32(result)) {
        return 0x7fc00000;
    }
    return result;
}

pub fn divFloat32(state: *arm_state.MachineState, left: u32, right: u32) u32 {
    const left_word = floatInput32(state, left);
    const right_word = floatInput32(state, right);
    var result = @bitCast(u32, @bitCast(f32, left_word) / @bitCast(f32, right_word));
    result = floatOutput32(state, result);
    if (state.floatDefaultNaN() and isNan32(result)) {
        return 0x7fc00000;
    }
    return result;
}

pub fn mulFloat32(state: *arm_state.MachineState, left: u32, right: u32) u32 {
    const left_word = floatInput32(state, left);
    const right_word = floatInput32(state, right);
    var result = @bitCast(u32, @bitCast(f32, left_word) * @bitCast(f32, right_word));
    result = floatOutput32(state, result);
    if (state.floatDefaultNaN() and isNan32(result)) {
        return 0x7fc00000;
    }
    return result;
}

pub fn subFloat32(state: *arm_state.MachineState, left: u32, right: u32) u32 {
    const left_word = floatInput32(state, left);
    const right_word = floatInput32(state, right);
    var result = @bitCast(u32, @bitCast(f32, left_word) - @bitCast(f32, right_word));
    result = floatOutput32(state, result);
    if (state.floatDefaultNaN() and isNan32(result)) {
        return 0x7fc00000;
    }
    return result;
}

pub fn negFloat32(value: u32) u32 {
    return value ^ 0x80000000;
}

pub fn sqrtFloat32(state: *arm_state.MachineState, value: u32) u32 {
    const input = floatInput32(state, value);
    var result = @bitCast(u32, @sqrt(@bitCast(f32, input)));
    result = floatOutput32(state, result);
    if (state.floatDefaultNaN() and isNan32(result)) {
        return 0x7fc00000;
    }
    return result;
}

pub fn addFloat64(state: *arm_state.MachineState, left: u64, right: u64) u64 {
    const left_word = floatInput64(state, left);
    const right_word = floatInput64(state, right);
    var result = @bitCast(u64, @bitCast(f64, left_word) + @bitCast(f64, right_word));
    result = floatOutput64(state, result);
    if (state.floatDefaultNaN() and isNan64(result)) {
        return 0x7ff8000000000000;
    }
    return result;
}

pub fn divFloat64(state: *arm_state.MachineState, left: u64, right: u64) u64 {
    const left_word = floatInput64(state, left);
    const right_word = floatInput64(state, right);
    var result = @bitCast(u64, @bitCast(f64, left_word) / @bitCast(f64, right_word));
    result = floatOutput64(state, result);
    if (state.floatDefaultNaN() and isNan64(result)) {
        return 0x7ff8000000000000;
    }
    return result;
}

pub fn mulFloat64(state: *arm_state.MachineState, left: u64, right: u64) u64 {
    const left_word = floatInput64(state, left);
    const right_word = floatInput64(state, right);
    var result = @bitCast(u64, @bitCast(f64, left_word) * @bitCast(f64, right_word));
    result = floatOutput64(state, result);
    if (state.floatDefaultNaN() and isNan64(result)) {
        return 0x7ff8000000000000;
    }
    return result;
}

pub fn negFloat64(value: u64) u64 {
    return value ^ 0x8000000000000000;
}

pub fn sqrtFloat64(state: *arm_state.MachineState, value: u64) u64 {
    const input = floatInput64(state, value);
    var result = @bitCast(u64, @sqrt(@bitCast(f64, input)));
    result = floatOutput64(state, result);
    if (state.floatDefaultNaN() and isNan64(result)) {
        return 0x7ff8000000000000;
    }
    return result;
}

pub fn subFloat64(state: *arm_state.MachineState, left: u64, right: u64) u64 {
    const left_word = floatInput64(state, left);
    const right_word = floatInput64(state, right);
    var result = @bitCast(u64, @bitCast(f64, left_word) - @bitCast(f64, right_word));
    result = floatOutput64(state, result);
    if (state.floatDefaultNaN() and isNan64(result)) {
        return 0x7ff8000000000000;
    }
    return result;
}

pub fn writeFloatCompare32(state: *arm_state.MachineState, left: u32, right: u32, invalid_on_quiet: bool) void {
    const left_word = floatInput32(state, left);
    const right_word = floatInput32(state, right);
    if (isNan32(left_word) or isNan32(right_word)) {
        if (invalid_on_quiet or isSignalingNan32(left_word) or isSignalingNan32(right_word)) {
            state.fpscr |= 1;
        }
        writeFloatNzcv(state, 0x30000000);
        return;
    }
    const left_value = @bitCast(f32, left_word);
    const right_value = @bitCast(f32, right_word);
    if (left_value == right_value) {
        writeFloatNzcv(state, 0x60000000);
    } else if (left_value < right_value) {
        writeFloatNzcv(state, 0x80000000);
    } else {
        writeFloatNzcv(state, 0x20000000);
    }
}

pub fn writeFloatCompare64(state: *arm_state.MachineState, left: u64, right: u64, invalid_on_quiet: bool) void {
    const left_word = floatInput64(state, left);
    const right_word = floatInput64(state, right);
    if (isNan64(left_word) or isNan64(right_word)) {
        if (invalid_on_quiet or isSignalingNan64(left_word) or isSignalingNan64(right_word)) {
            state.fpscr |= 1;
        }
        writeFloatNzcv(state, 0x30000000);
        return;
    }
    const left_value = @bitCast(f64, left_word);
    const right_value = @bitCast(f64, right_word);
    if (left_value == right_value) {
        writeFloatNzcv(state, 0x60000000);
    } else if (left_value < right_value) {
        writeFloatNzcv(state, 0x80000000);
    } else {
        writeFloatNzcv(state, 0x20000000);
    }
}

pub fn writeFloatNzcv(state: *arm_state.MachineState, value: u32) void {
    state.fpscr = mergeStatus(state.fpscr, value, 0xf0000000);
}

pub fn convertFloat32To64(state: *arm_state.MachineState, value: u32) u64 {
    const input = floatInput32(state, value);
    var result = @bitCast(u64, @floatCast(f64, @bitCast(f32, input)));
    result = floatOutput64(state, result);
    if (state.floatDefaultNaN() and isNan64(result)) {
        return 0x7ff8000000000000;
    }
    return result;
}

pub fn convertFloat64To32(state: *arm_state.MachineState, value: u64) u32 {
    const input = floatInput64(state, value);
    var result = @bitCast(u32, @floatCast(f32, @bitCast(f64, input)));
    result = floatOutput32(state, result);
    if (state.floatDefaultNaN() and isNan32(result)) {
        return 0x7fc00000;
    }
    return result;
}

fn scaleConverted32(value: u32, fractional_bits: usize) u32 {
    if (fractional_bits == 0 or value == 0) {
        return value;
    }
    const exponent = @intCast(u32, 127 - @intCast(i32, fractional_bits));
    return @bitCast(u32, @bitCast(f32, value) * @bitCast(f32, exponent << 23));
}

fn scaleConverted64(value: u64, fractional_bits: usize) u64 {
    if (fractional_bits == 0 or value == 0) {
        return value;
    }
    const exponent = @intCast(u64, 1023 - @intCast(i32, fractional_bits));
    return @bitCast(u64, @bitCast(f64, value) * @bitCast(f64, exponent << 52));
}

pub fn floatFromSigned32To32(state: *arm_state.MachineState, value: u32, fractional_bits: usize) u32 {
    return floatOutput32(state, scaleConverted32(@bitCast(u32, @intToFloat(f32, @bitCast(i32, value))), fractional_bits));
}

pub fn floatFromUnsigned32To32(state: *arm_state.MachineState, value: u32, fractional_bits: usize) u32 {
    return floatOutput32(state, scaleConverted32(@bitCast(u32, @intToFloat(f32, value)), fractional_bits));
}

pub fn floatFromSigned32To64(state: *arm_state.MachineState, value: u32, fractional_bits: usize) u64 {
    return floatOutput64(state, scaleConverted64(@bitCast(u64, @intToFloat(f64, @bitCast(i32, value))), fractional_bits));
}

pub fn floatFromUnsigned32To64(state: *arm_state.MachineState, value: u32, fractional_bits: usize) u64 {
    return floatOutput64(state, scaleConverted64(@bitCast(u64, @intToFloat(f64, value)), fractional_bits));
}

pub fn convertFloat32ToSigned32(state: *arm_state.MachineState, value: u32, round_towards_zero: bool) u32 {
    const rounded = roundedFloat64(state, @floatCast(f64, @bitCast(f32, floatInput32(state, value))), round_towards_zero);
    return intWordFromSignedFloat(rounded);
}

pub fn convertFloat64ToSigned32(state: *arm_state.MachineState, value: u64, round_towards_zero: bool) u32 {
    const rounded = roundedFloat64(state, @bitCast(f64, floatInput64(state, value)), round_towards_zero);
    return intWordFromSignedFloat(rounded);
}

pub fn convertFloat32ToUnsigned32(state: *arm_state.MachineState, value: u32, round_towards_zero: bool) u32 {
    const rounded = roundedFloat64(state, @floatCast(f64, @bitCast(f32, floatInput32(state, value))), round_towards_zero);
    return intWordFromUnsignedFloat(rounded);
}

pub fn convertFloat64ToUnsigned32(state: *arm_state.MachineState, value: u64, round_towards_zero: bool) u32 {
    const rounded = roundedFloat64(state, @bitCast(f64, floatInput64(state, value)), round_towards_zero);
    return intWordFromUnsignedFloat(rounded);
}

pub fn roundedFloat64(state: *const arm_state.MachineState, value: f64, round_towards_zero: bool) f64 {
    if (round_towards_zero) {
        return @trunc(value);
    }
    return switch (state.floatRoundMode()) {
        .nearest => if (value >= 0) @floor(value + 0.5) else @ceil(value - 0.5),
        .positive => @ceil(value),
        .negative => @floor(value),
        .nearest_away => if (value >= 0) @floor(value + 0.5) else @ceil(value - 0.5),
        .zero => @trunc(value),
    };
}

pub fn intWordFromSignedFloat(value: f64) u32 {
    if (value != value) {
        return 0;
    }
    if (value >= 2147483647.0) {
        return 0x7fffffff;
    }
    if (value <= -2147483648.0) {
        return 0x80000000;
    }
    return @bitCast(u32, @floatToInt(i32, value));
}

pub fn intWordFromUnsignedFloat(value: f64) u32 {
    if (value != value or value <= 0.0) {
        return 0;
    }
    if (value >= 4294967295.0) {
        return 0xffffffff;
    }
    return @floatToInt(u32, value);
}

pub fn floatInput32(state: *arm_state.MachineState, value: u32) u32 {
    if (state.floatFlushZero() and isDenormal32(value)) {
        state.fpscr |= 1 << 7;
        return 0;
    }
    return value;
}

pub fn floatInput64(state: *arm_state.MachineState, value: u64) u64 {
    if (state.floatFlushZero() and isDenormal64(value)) {
        state.fpscr |= 1 << 7;
        return 0;
    }
    return value;
}

pub fn floatOutput32(state: *arm_state.MachineState, value: u32) u32 {
    if (state.floatFlushZero() and isDenormal32(value)) {
        state.fpscr |= 1 << 3;
        return 0;
    }
    return value;
}

pub fn floatOutput64(state: *arm_state.MachineState, value: u64) u64 {
    if (state.floatFlushZero() and isDenormal64(value)) {
        state.fpscr |= 1 << 3;
        return 0;
    }
    return value;
}

pub fn isDenormal32(value: u32) bool {
    const magnitude = value & 0x7fffffff;
    return magnitude != 0 and magnitude <= 0x007fffff;
}

pub fn isDenormal64(value: u64) bool {
    const magnitude = value & 0x7fffffffffffffff;
    return magnitude != 0 and magnitude <= 0x000fffffffffffff;
}

pub fn isNan32(value: u32) bool {
    return (value & 0x7fffffff) > 0x7f800000;
}

pub fn isNan64(value: u64) bool {
    return (value & 0x7fffffffffffffff) > 0x7ff0000000000000;
}

pub fn isSignalingNan32(value: u32) bool {
    return isNan32(value) and (value & 0x00400000) == 0;
}

pub fn isSignalingNan64(value: u64) bool {
    return isNan64(value) and (value & 0x0008000000000000) == 0;
}

pub fn floatWordIndex(value: u32, high: bool) arm_state.FloatWordReg {
    const index = @intCast(u5, ((value & 0xf) << 1) | @as(u32, @boolToInt(high)));
    return @intToEnum(arm_state.FloatWordReg, index);
}

pub fn floatPairIndex(value: u32, high: bool) arm_state.FloatPairReg {
    const index = @intCast(u5, (value & 0xf) | (@as(u32, @boolToInt(high)) << 4));
    return @intToEnum(arm_state.FloatPairReg, index);
}

pub fn floatVectorPlan(state: *const arm_state.MachineState, double: bool, dest: u32, source: u32) ArmStepError!FloatVectorPlan {
    const length = state.floatVectorLength();
    const stride = state.floatVectorStride();
    if (stride == 0) {
        return error.Unpredictable;
    }

    const bank_size = if (double) @as(u32, 4) else @as(u32, 8);
    if (stride * length > bank_size or (length == 1 and stride != 1)) {
        return error.Unpredictable;
    }

    const dest_scalar = if (double) isScalarFloatPairIndex(dest) else isScalarFloatWordIndex(dest);
    const source_scalar = if (double) isScalarFloatPairIndex(source) else isScalarFloatWordIndex(source);
    return FloatVectorPlan{
        .count = if (dest_scalar) @as(u32, 1) else length,
        .stride = stride,
        .source_scalar = source_scalar,
    };
}

pub fn isScalarFloatWordIndex(index: u32) bool {
    return index < 8;
}

pub fn isScalarFloatPairIndex(index: u32) bool {
    return index < 4 or (index >= 16 and index < 20);
}

pub fn advanceFloatIndex(index: u32, stride: u32, bank_size: u32) u32 {
    const bank_start = index - (index % bank_size);
    return bank_start + (((index - bank_start) + stride) % bank_size);
}

pub fn readFloatWordAt(state: *const arm_state.MachineState, index: u32) u32 {
    return state.readFloatWord(@intToEnum(arm_state.FloatWordReg, @intCast(u5, index)));
}

pub fn writeFloatWordAt(state: *arm_state.MachineState, index: u32, value: u32) void {
    state.writeFloatWord(@intToEnum(arm_state.FloatWordReg, @intCast(u5, index)), value);
}

pub fn readFloatPairAt(state: *const arm_state.MachineState, index: u32) u64 {
    return readFloatPair(state, @intToEnum(arm_state.FloatPairReg, @intCast(u5, index)));
}

pub fn writeFloatPairAt(state: *arm_state.MachineState, index: u32, value: u64) void {
    writeFloatPair(state, @intToEnum(arm_state.FloatPairReg, @intCast(u5, index)), value);
}

pub fn floatStackBase(word: u32, double: bool) u32 {
    const value = (word >> 12) & 0xf;
    const high = @as(u32, @boolToInt(bits.getBit32(word, 22)));
    if (double) {
        return value | (high << 4);
    }
    return (value << 1) | high;
}

pub fn floatStackCount(word: u32) u32 {
    if (bits.getBit32(word, 8)) {
        return (word & 0xff) >> 1;
    }
    return word & 0xff;
}

pub fn isLastFloatWord(reg: arm_state.FloatWordReg) bool {
    return @enumToInt(reg) == 31;
}

pub fn nextFloatWordReg(reg: arm_state.FloatWordReg) arm_state.FloatWordReg {
    return @intToEnum(arm_state.FloatWordReg, @intCast(u5, @enumToInt(reg) + 1));
}

pub fn regListCount(list: u16) u5 {
    var count: u5 = 0;
    var index: u5 = 0;
    while (index < 16) : (index += 1) {
        if ((list & (@as(u16, 1) << index)) != 0) {
            count += 1;
        }
    }
    return count;
}

pub fn statusWriteField(word: u32) u4 {
    return @intCast(u4, (word >> 16) & 0xf);
}

pub fn statusWriteMask(field: u4) u32 {
    var mask: u32 = 0;
    if ((field & 0x8) != 0) {
        mask |= 0xf8000000;
    }
    if ((field & 0x4) != 0) {
        mask |= 0x000f0000;
    }
    if ((field & 0x2) != 0) {
        mask |= 0x00000200;
    }
    return mask;
}

pub fn mergeStatus(old: u32, value: u32, mask: u32) u32 {
    return (old & ~mask) | (value & mask);
}

pub fn readFloatPair(state: *const arm_state.MachineState, reg: arm_state.FloatPairReg) u64 {
    return state.readFloatPair(reg);
}

pub fn writeFloatPair(state: *arm_state.MachineState, reg: arm_state.FloatPairReg, value: u64) void {
    state.writeFloatPair(reg, value);
}
