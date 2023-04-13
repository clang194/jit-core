pub fn getBit32(value: u32, index: u5) bool {
    return ((value >> index) & 1) != 0;
}

pub fn setBit32(value: u32, index: u5, enabled: bool) u32 {
    const mask = @as(u32, 1) << index;
    if (enabled) {
        return value | mask;
    }
    return value & ~mask;
}

pub fn clearBit32(value: u32, index: u5) u32 {
    return setBit32(value, index, false);
}

pub fn ones32(comptime count: u6) u32 {
    if (count == 0) {
        return 0;
    }
    if (count >= 32) {
        return ~@as(u32, 0);
    }
    return (@as(u32, 1) << @intCast(u5, count)) - 1;
}

pub fn rangeMask32(comptime first: u5, comptime last: u5) u32 {
    if (first > last) {
        @compileError("invalid bit range");
    }
    return ones32(@as(u6, last) - @as(u6, first) + 1) << first;
}

pub fn clearBits32(value: u32, comptime first: u5, comptime last: u5) u32 {
    return value & ~rangeMask32(first, last);
}

pub fn modifyBits32(value: u32, new_bits: u32, comptime first: u5, comptime last: u5) u32 {
    const mask = rangeMask32(first, last);
    return clearBits32(value, first, last) | ((new_bits << first) & mask);
}

pub fn getBit64(value: u64, index: u6) bool {
    return ((value >> index) & 1) != 0;
}

pub fn setBit64(value: u64, index: u6, enabled: bool) u64 {
    const mask = @as(u64, 1) << index;
    if (enabled) {
        return value | mask;
    }
    return value & ~mask;
}

pub fn clearBit64(value: u64, index: u6) u64 {
    return setBit64(value, index, false);
}

pub fn ones64(comptime count: u7) u64 {
    if (count == 0) {
        return 0;
    }
    if (count >= 64) {
        return ~@as(u64, 0);
    }
    return (@as(u64, 1) << @intCast(u6, count)) - 1;
}

pub fn rangeMask64(comptime first: u6, comptime last: u6) u64 {
    if (first > last) {
        @compileError("invalid bit range");
    }
    return ones64(@as(u7, last) - @as(u7, first) + 1) << first;
}

pub fn clearBits64(value: u64, comptime first: u6, comptime last: u6) u64 {
    return value & ~rangeMask64(first, last);
}

pub fn modifyBits64(value: u64, new_bits: u64, comptime first: u6, comptime last: u6) u64 {
    const mask = rangeMask64(first, last);
    return clearBits64(value, first, last) | ((new_bits << first) & mask);
}

pub fn lowByte(value: u32) u8 {
    return @intCast(u8, value & 0xff);
}

pub fn swapBytes16(value: u16) u16 {
    return @intCast(u16, (@as(u32, value) >> 8) | (@as(u32, value) << 8));
}

pub fn swapBytes32(value: u32) u32 {
    return ((value & 0x000000ff) << 24) |
        ((value & 0x0000ff00) << 8) |
        ((value & 0x00ff0000) >> 8) |
        ((value & 0xff000000) >> 24);
}

pub fn swapLaneBytes32(value: u32) u32 {
    return ((value & 0x00ff00ff) << 8) | ((value & 0xff00ff00) >> 8);
}

pub fn swapBytes64(value: u64) u64 {
    return ((value & 0x00000000000000ff) << 56) |
        ((value & 0x000000000000ff00) << 40) |
        ((value & 0x0000000000ff0000) << 24) |
        ((value & 0x00000000ff000000) << 8) |
        ((value & 0x000000ff00000000) >> 8) |
        ((value & 0x0000ff0000000000) >> 24) |
        ((value & 0x00ff000000000000) >> 40) |
        ((value & 0xff00000000000000) >> 56);
}

pub fn topBit(value: u32) bool {
    return (value & 0x80000000) != 0;
}

pub fn topBit64(value: u64) bool {
    return (value & 0x8000000000000000) != 0;
}

pub fn isZero(value: u32) bool {
    return value == 0;
}

pub fn shiftLeft32(value: u32, amount: i32) u32 {
    if (amount < 0) {
        return shiftRight32(value, -amount);
    }
    if (amount >= 32) {
        return 0;
    }
    return value << @intCast(u5, amount);
}

pub fn shiftRight32(value: u32, amount: i32) u32 {
    if (amount < 0) {
        return shiftLeft32(value, -amount);
    }
    if (amount >= 32) {
        return 0;
    }
    return value >> @intCast(u5, amount);
}

pub fn rotateRight32(value: u32, amount: u5) u32 {
    if (amount == 0) {
        return value;
    }
    return (value >> amount) | (value << @intCast(u5, 32 - @as(u6, amount)));
}

pub fn signedShiftLeft32(value: u32, amount: i32) u32 {
    return shiftLeft32(value, amount);
}

pub fn signedShiftRight32(value: u32, amount: i32) u32 {
    if (amount < 0) {
        return signedShiftLeft32(value, -amount);
    }
    if (amount >= 32) {
        return if (topBit(value)) ~@as(u32, 0) else 0;
    }
    return @bitCast(u32, @bitCast(i32, value) >> @intCast(u5, amount));
}

pub fn shiftPairRight32(high: u32, low: u32, amount: i32) u32 {
    return shiftLeft32(high, 32 - amount) | shiftRight32(low, amount);
}

pub fn signedShiftPairRight32(high: u32, low: u32, amount: i32) u32 {
    return signedShiftLeft32(high, 32 - amount) | shiftRight32(low, amount);
}

pub fn negate32(value: u32) u32 {
    return 0 -% value;
}

pub fn shiftLeft64(value: u64, amount: i32) u64 {
    if (amount < 0) {
        return shiftRight64(value, -amount);
    }
    if (amount >= 64) {
        return 0;
    }
    return value << @intCast(u6, amount);
}

pub fn shiftRight64(value: u64, amount: i32) u64 {
    if (amount < 0) {
        return shiftLeft64(value, -amount);
    }
    if (amount >= 64) {
        return 0;
    }
    return value >> @intCast(u6, amount);
}

pub fn signedShiftLeft64(value: u64, amount: i32) u64 {
    return shiftLeft64(value, amount);
}

pub fn signedShiftRight64(value: u64, amount: i32) u64 {
    if (amount < 0) {
        return signedShiftLeft64(value, -amount);
    }
    if (amount >= 64) {
        return if (topBit64(value)) ~@as(u64, 0) else 0;
    }
    return @bitCast(u64, @bitCast(i64, value) >> @intCast(u6, amount));
}

pub fn shiftPairRight64(high: u64, low: u64, amount: i32) u64 {
    return shiftLeft64(high, 64 - amount) | shiftRight64(low, amount);
}

pub fn signedShiftPairRight64(high: u64, low: u64, amount: i32) u64 {
    return signedShiftLeft64(high, 64 - amount) | shiftRight64(low, amount);
}

pub fn negate64(value: u64) u64 {
    return 0 -% value;
}

pub const CarryWord = struct {
    word: u32,
    carry: bool,
};

pub fn rotateRightThroughCarry(value: u32, carry_in: bool) CarryWord {
    const high = if (carry_in) @as(u32, 0x80000000) else @as(u32, 0);
    return CarryWord{
        .word = (value >> 1) | high,
        .carry = getBit32(value, 0),
    };
}

pub fn countLow16(value: u16) u8 {
    var remaining = value;
    var count: u8 = 0;
    while (remaining != 0) {
        count += @intCast(u8, remaining & 1);
        remaining >>= 1;
    }
    return count;
}

pub fn firstSetLow8(value: u8) u4 {
    var remaining = value;
    var index: u4 = 0;
    while (index < 8) : (index += 1) {
        if ((remaining & 1) != 0) {
            return index;
        }
        remaining >>= 1;
    }
    return 8;
}

pub fn signExtend32(value: u32, comptime width: u5) i32 {
    const high = @as(u32, 1) << (width - 1);
    const mask = (@as(u32, 1) << width) - 1;
    var narrowed = value & mask;
    if ((narrowed & high) != 0) {
        narrowed |= ~mask;
    }
    return @bitCast(i32, narrowed);
}

pub fn signExtend64(value: u64, comptime width: u6) i64 {
    const high = @as(u64, 1) << (width - 1);
    const mask = (@as(u64, 1) << width) - 1;
    var narrowed = value & mask;
    if ((narrowed & high) != 0) {
        narrowed |= ~mask;
    }
    return @bitCast(i64, narrowed);
}
