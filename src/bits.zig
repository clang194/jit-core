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

pub fn lowByte(value: u32) u8 {
    return @intCast(u8, value & 0xff);
}

pub fn topBit(value: u32) bool {
    return (value & 0x80000000) != 0;
}

pub fn isZero(value: u32) bool {
    return value == 0;
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

