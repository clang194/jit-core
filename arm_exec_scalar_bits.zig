const arm_state = @import("arm_state.zig");
const bits = @import("bits.zig");
usingnamespace @import("arm_exec_types.zig");
usingnamespace @import("arm_exec_fetch_decode.zig");
usingnamespace @import("arm_exec_dispatch.zig");
usingnamespace @import("arm_exec_coprocessor.zig");
usingnamespace @import("arm_exec_float_decode.zig");
usingnamespace @import("arm_exec_float_run.zig");
usingnamespace @import("arm_exec_multiply_run.zig");
usingnamespace @import("arm_exec_float_math.zig");
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

pub fn addSigned(value: u32, offset: i32) u32 {
    if (offset < 0) {
        return value -% @intCast(u32, -offset);
    }
    return value +% @intCast(u32, offset);
}

pub fn readLong(state: *const arm_state.MachineState, high: arm_state.ArmReg, low: arm_state.ArmReg) u64 {
    return (@as(u64, state.read(high)) << 32) | @as(u64, state.read(low));
}

pub fn writeLongResult(state: *arm_state.MachineState, high: arm_state.ArmReg, low: arm_state.ArmReg, value: u64) void {
    state.write(low, @intCast(u32, value & 0xffffffff));
    state.write(high, @intCast(u32, value >> 32));
}

pub fn signedProduct(left: u32, right: u32) u64 {
    const wide_left = @as(i64, @bitCast(i32, left));
    const wide_right = @as(i64, @bitCast(i32, right));
    return @bitCast(u64, wide_left * wide_right);
}

pub fn rotateRightWord(value: u32, amount: u8) u32 {
    const shift = amount & 31;
    if (shift == 0) {
        return value;
    }
    return (value >> @intCast(u5, shift)) | (value << @intCast(u5, 32 - shift));
}

pub fn addHalfPairs(left: u32, right: u32) u32 {
    const low = (left +% right) & 0xffff;
    const high = ((left >> 16) +% (right >> 16)) & 0xffff;
    return low | (high << 16);
}

pub fn countLeadingZeros32(value: u32) u32 {
    var mask: u32 = 0x80000000;
    var count: u32 = 0;
    while (mask != 0 and (value & mask) == 0) : (mask >>= 1) {
        count += 1;
    }
    return count;
}

pub fn logicalLeft(value: u32, amount: u8, carry_in: bool) ShiftResult {
    if (amount == 0) {
        return ShiftResult{ .word = value, .carry = carry_in };
    }
    if (amount < 32) {
        return ShiftResult{
            .word = value << @intCast(u5, amount),
            .carry = bits.getBit32(value, @intCast(u5, 32 - amount)),
        };
    }
    if (amount == 32) {
        return ShiftResult{ .word = 0, .carry = bits.getBit32(value, 0) };
    }
    return ShiftResult{ .word = 0, .carry = false };
}

pub fn logicalRight(value: u32, amount: u8, carry_in: bool) ShiftResult {
    if (amount == 0) {
        return ShiftResult{ .word = value, .carry = carry_in };
    }
    if (amount < 32) {
        return ShiftResult{
            .word = value >> @intCast(u5, amount),
            .carry = bits.getBit32(value, @intCast(u5, amount - 1)),
        };
    }
    if (amount == 32) {
        return ShiftResult{ .word = 0, .carry = bits.getBit32(value, 31) };
    }
    return ShiftResult{ .word = 0, .carry = false };
}

pub fn arithmeticRight(value: u32, amount: u8, carry_in: bool) ShiftResult {
    if (amount == 0) {
        return ShiftResult{ .word = value, .carry = carry_in };
    }
    if (amount < 32) {
        const shift = @intCast(u5, amount);
        const fill = if (bits.topBit(value)) ~(@as(u32, 0xffffffff) >> shift) else @as(u32, 0);
        return ShiftResult{
            .word = (value >> shift) | fill,
            .carry = bits.getBit32(value, @intCast(u5, amount - 1)),
        };
    }
    if (bits.topBit(value)) {
        return ShiftResult{ .word = 0xffffffff, .carry = true };
    }
    return ShiftResult{ .word = 0, .carry = false };
}

pub fn rotateRight(value: u32, amount: u8, carry_in: bool) ShiftResult {
    if (amount == 0) {
        return ShiftResult{ .word = value, .carry = carry_in };
    }
    const shift = amount & 31;
    if (shift == 0) {
        return ShiftResult{ .word = value, .carry = bits.topBit(value) };
    }
    const word = (value >> @intCast(u5, shift)) | (value << @intCast(u5, 32 - shift));
    return ShiftResult{ .word = word, .carry = bits.topBit(word) };
}

pub fn byteReverseWord(value: u32) u32 {
    return ((value & 0x000000ff) << 24) |
        ((value & 0x0000ff00) << 8) |
        ((value & 0x00ff0000) >> 8) |
        ((value & 0xff000000) >> 24);
}

pub fn byteReverseHalf(value: u32) u32 {
    return ((value & 0xff) << 8) | ((value >> 8) & 0xff);
}

pub fn byteReverseHalfwords(value: u32) u32 {
    return ((value & 0x00ff00ff) << 8) | ((value & 0xff00ff00) >> 8);
}

pub fn signExtendByte(value: u32) u32 {
    const narrowed = value & 0xff;
    if ((narrowed & 0x80) != 0) {
        return narrowed | 0xffffff00;
    }
    return narrowed;
}

pub fn signExtendBytePairs(value: u32) u32 {
    const low = signExtendByte(value) & 0xffff;
    const high = signExtendByte(value >> 16) & 0xffff;
    return low | (high << 16);
}

pub fn signedByte(value: u32) i16 {
    const narrowed = @intCast(i16, value & 0xff);
    if ((narrowed & 0x80) != 0) {
        return narrowed - 256;
    }
    return narrowed;
}

pub fn clampSignedByte(value: i16) i16 {
    if (value > 127) {
        return 127;
    }
    if (value < -128) {
        return -128;
    }
    return value;
}

pub fn signedHalf(value: u32) i32 {
    const narrowed = @intCast(i32, value & 0xffff);
    if ((narrowed & 0x8000) != 0) {
        return narrowed - 65536;
    }
    return narrowed;
}

pub fn clampSignedHalfWord(value: i32) i32 {
    if (value > 32767) {
        return 32767;
    }
    if (value < -32768) {
        return -32768;
    }
    return value;
}

pub fn clampUnsignedHalfWord(value: i32) u16 {
    if (value > 65535) {
        return 0xffff;
    }
    if (value < 0) {
        return 0;
    }
    return @intCast(u16, value);
}

pub fn signExtendHalf(value: u32) u32 {
    const narrowed = value & 0xffff;
    if ((narrowed & 0x8000) != 0) {
        return narrowed | 0xffff0000;
    }
    return narrowed;
}

pub fn selectedHalf(value: u32, high: bool) i32 {
    return signedHalf(if (high) value >> 16 else value);
}

pub fn signedLowWord(value: i64) u32 {
    return @intCast(u32, @bitCast(u64, value) & 0xffffffff);
}

pub fn addWithCarry(left: u32, right: u32, carry_in: bool) AddResult {
    const carry: u64 = if (carry_in) 1 else 0;
    const wide = @as(u64, left) + @as(u64, right) + carry;
    const result = @intCast(u32, wide & 0xffffffff);
    const overflow = ((~(left ^ right) & (left ^ result)) & 0x80000000) != 0;
    return AddResult{
        .word = result,
        .carry = wide > 0xffffffff,
        .overflow = overflow,
    };
}

pub fn subWithCarry(left: u32, right: u32, carry_in: bool) AddResult {
    return addWithCarry(left, ~right, carry_in);
}
