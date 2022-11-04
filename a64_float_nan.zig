const a64_state = @import("a64_state.zig");
const float_exception = @import("float_exception.zig");
const float_format = @import("float_format.zig");
const float_status = @import("float_status.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

fn withoutSign(comptime Format: type, value: anytype) @TypeOf(value) {
    return value & ~Format.sign_mask;
}

fn isDenormal(comptime Format: type, value: anytype) bool {
    const magnitude = withoutSign(Format, value);
    return magnitude != 0 and magnitude <= Format.fraction_mask;
}

fn isNan(comptime Format: type, value: anytype) bool {
    return withoutSign(Format, value) > Format.infinity(false);
}

fn quietMask(comptime Format: type) @TypeOf(Format.exponent_mask) {
    return Format.exponent_mask | Format.fraction_top_bit;
}

fn isQuietNan(comptime Format: type, value: anytype) bool {
    const mask = quietMask(Format);
    return (value & mask) == mask;
}

fn isSignalingNan(comptime Format: type, value: anytype) bool {
    return (value & quietMask(Format)) == Format.exponent_mask and (value & Format.fraction_mask) != 0;
}

fn quietNan(comptime Format: type, value: anytype) @TypeOf(value) {
    return value | Format.fraction_top_bit;
}

fn processNan(comptime Format: type, control: a64_state.FloatControl, value: anytype, status: *float_status.FloatStatus) float_exception.FloatExceptionError!@TypeOf(value) {
    var result = value;
    if (isSignalingNan(Format, value)) {
        result = quietNan(Format, result);
        try float_exception.processFloatException(.invalid_operation, control, status);
    }
    if (control.dn()) {
        return Format.defaultNan();
    }
    return result;
}

fn processPairNan(comptime Format: type, control: a64_state.FloatControl, left: anytype, right: @TypeOf(left), status: *float_status.FloatStatus) float_exception.FloatExceptionError!?@TypeOf(left) {
    const values = [_]@TypeOf(left){ left, right };
    for (values) |value| {
        if (isSignalingNan(Format, value)) {
            return try processNan(Format, control, value, status);
        }
    }
    for (values) |value| {
        if (isQuietNan(Format, value)) {
            return try processNan(Format, control, value, status);
        }
    }
    return null;
}

fn processTernaryNan(comptime Format: type, control: a64_state.FloatControl, first: anytype, second: @TypeOf(first), third: @TypeOf(first), status: *float_status.FloatStatus) float_exception.FloatExceptionError!?@TypeOf(first) {
    const values = [_]@TypeOf(first){ first, second, third };
    for (values) |value| {
        if (isSignalingNan(Format, value)) {
            return try processNan(Format, control, value, status);
        }
    }
    for (values) |value| {
        if (isQuietNan(Format, value)) {
            return try processNan(Format, control, value, status);
        }
    }
    return null;
}

fn chooseUnaryNan(comptime Format: type, control: a64_state.FloatControl, mode: FloatNanMode64, value: anytype) ?@TypeOf(value) {
    if (!useAccurateNan(mode) or control.dn()) {
        return null;
    }
    if (isSignalingNan(Format, value)) {
        return quietNan(Format, value);
    }
    if (isQuietNan(Format, value)) {
        return value;
    }
    return null;
}

fn choosePairNan(comptime Format: type, control: a64_state.FloatControl, mode: FloatNanMode64, left: anytype, right: @TypeOf(left)) ?@TypeOf(left) {
    if (!useAccurateNan(mode) or control.dn()) {
        return null;
    }
    const values = [_]@TypeOf(left){ left, right };
    for (values) |value| {
        if (isSignalingNan(Format, value)) {
            return quietNan(Format, value);
        }
    }
    for (values) |value| {
        if (isQuietNan(Format, value)) {
            return value;
        }
    }
    return null;
}

fn chooseTernaryNan(comptime Format: type, control: a64_state.FloatControl, mode: FloatNanMode64, first: anytype, second: @TypeOf(first), third: @TypeOf(first)) ?@TypeOf(first) {
    if (!useAccurateNan(mode) or control.dn()) {
        return null;
    }
    const values = [_]@TypeOf(first){ first, second, third };
    for (values) |value| {
        if (isSignalingNan(Format, value)) {
            return quietNan(Format, value);
        }
    }
    for (values) |value| {
        if (isQuietNan(Format, value)) {
            return value;
        }
    }
    return null;
}

pub fn isDenormal32(value: u32) bool {
    return isDenormal(float_format.Binary32, value);
}

pub fn isDenormal64(value: u64) bool {
    return isDenormal(float_format.Binary64, value);
}

pub fn isNan32(value: u32) bool {
    return isNan(float_format.Binary32, value);
}

pub fn isNan64(value: u64) bool {
    return isNan(float_format.Binary64, value);
}

pub fn isQuietNan32(value: u32) bool {
    return isQuietNan(float_format.Binary32, value);
}

pub fn isSignalingNan32(value: u32) bool {
    return isSignalingNan(float_format.Binary32, value);
}

pub fn isQuietNan64(value: u64) bool {
    return isQuietNan(float_format.Binary64, value);
}

pub fn isSignalingNan64(value: u64) bool {
    return isSignalingNan(float_format.Binary64, value);
}

pub fn processNan32(control: a64_state.FloatControl, value: u32, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u32 {
    return processNan(float_format.Binary32, control, value, status);
}

pub fn processNan64(control: a64_state.FloatControl, value: u64, status: *float_status.FloatStatus) float_exception.FloatExceptionError!u64 {
    return processNan(float_format.Binary64, control, value, status);
}

pub fn processPairNan32(control: a64_state.FloatControl, left: u32, right: u32, status: *float_status.FloatStatus) float_exception.FloatExceptionError!?u32 {
    return processPairNan(float_format.Binary32, control, left, right, status);
}

pub fn processPairNan64(control: a64_state.FloatControl, left: u64, right: u64, status: *float_status.FloatStatus) float_exception.FloatExceptionError!?u64 {
    return processPairNan(float_format.Binary64, control, left, right, status);
}

pub fn processTernaryNan32(control: a64_state.FloatControl, first: u32, second: u32, third: u32, status: *float_status.FloatStatus) float_exception.FloatExceptionError!?u32 {
    return processTernaryNan(float_format.Binary32, control, first, second, third, status);
}

pub fn processTernaryNan64(control: a64_state.FloatControl, first: u64, second: u64, third: u64, status: *float_status.FloatStatus) float_exception.FloatExceptionError!?u64 {
    return processTernaryNan(float_format.Binary64, control, first, second, third, status);
}

pub fn chooseBinaryNan32(control: a64_state.FloatControl, mode: FloatNanMode64, left: u32, right: u32) ?u32 {
    return choosePairNan(float_format.Binary32, control, mode, left, right);
}

pub fn chooseBinaryNan64(control: a64_state.FloatControl, mode: FloatNanMode64, left: u64, right: u64) ?u64 {
    return choosePairNan(float_format.Binary64, control, mode, left, right);
}

pub fn chooseTernaryNan32(control: a64_state.FloatControl, mode: FloatNanMode64, first: u32, second: u32, third: u32) ?u32 {
    return chooseTernaryNan(float_format.Binary32, control, mode, first, second, third);
}

pub fn chooseTernaryNan64(control: a64_state.FloatControl, mode: FloatNanMode64, first: u64, second: u64, third: u64) ?u64 {
    return chooseTernaryNan(float_format.Binary64, control, mode, first, second, third);
}

pub fn chooseUnaryNan32(control: a64_state.FloatControl, mode: FloatNanMode64, value: u32) ?u32 {
    return chooseUnaryNan(float_format.Binary32, control, mode, value);
}

pub fn chooseUnaryNan64(control: a64_state.FloatControl, mode: FloatNanMode64, value: u64) ?u64 {
    return chooseUnaryNan(float_format.Binary64, control, mode, value);
}
