const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub fn readLittle64(memory: [*]u8, offset: usize) u64 {
    var value: u64 = 0;
    var index: usize = 0;
    while (index < 8) : (index += 1) {
        value |= @as(u64, memory[offset + index]) << @intCast(u6, index * 8);
    }
    return value;
}

pub fn writeLittle64(memory: [*]u8, offset: usize, value: u64) void {
    var index: usize = 0;
    while (index < 8) : (index += 1) {
        memory[offset + index] = @intCast(u8, (value >> @intCast(u6, index * 8)) & 0xff);
    }
}

pub fn regFromWord(value: u32) a64_state.GeneralReg {
    return @intToEnum(a64_state.GeneralReg, @intCast(u5, value & 0x1f));
}

pub fn vectorRegFromWord(value: u32) a64_state.VectorReg {
    return @intToEnum(a64_state.VectorReg, @intCast(u5, value & 0x1f));
}

pub fn shift32(value: u32, shift: u2, amount: u5) u32 {
    switch (shift) {
        0 => return value << amount,
        1 => return value >> amount,
        2 => return @bitCast(u32, @bitCast(i32, value) >> amount),
        else => return rotateRight32(value, amount),
    }
}

pub fn shift64(value: u64, shift: u2, amount: u6) u64 {
    switch (shift) {
        0 => return value << amount,
        1 => return value >> amount,
        2 => return @bitCast(u64, @bitCast(i64, value) >> amount),
        else => return bits.rotateRight64(value, amount),
    }
}

pub fn rotateRight32(value: u32, amount: u5) u32 {
    const shift = amount & 31;
    if (shift == 0) {
        return value;
    }
    return (value >> shift) | (value << @intCast(u5, 32 - shift));
}
