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

pub fn lowByte(value: u32) u8 {
    return @intCast(u8, value & 0xff);
}

pub fn topBit(value: u32) bool {
    return (value & 0x80000000) != 0;
}

pub fn isZero(value: u32) bool {
    return value == 0;
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
