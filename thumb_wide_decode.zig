const bits = @import("bits.zig");

pub fn branchLinkTarget(word: u32, pc: u32) ?u32 {
    const first = @intCast(u16, word & 0xffff);
    const second = @intCast(u16, (word >> 16) & 0xffff);
    if ((first & 0xf800) != 0xf000 or (second & 0xf800) != 0xf800) {
        return null;
    }
    return @bitCast(u32, @intCast(i32, pc + 4) + wideOffset(word));
}

pub fn branchLinkExchangeTarget(word: u32, pc: u32) error{Unpredictable}!?u32 {
    const first = @intCast(u16, word & 0xffff);
    const second = @intCast(u16, (word >> 16) & 0xffff);
    if ((first & 0xf800) != 0xf000 or (second & 0xf800) != 0xe800) {
        return null;
    }
    if ((second & 1) != 0) {
        return error.Unpredictable;
    }
    return @bitCast(u32, @intCast(i32, alignDown4(pc + 4)) + wideOffset(word));
}

fn alignDown4(value: u32) u32 {
    return value & 0xfffffffc;
}

fn wideOffset(word: u32) i32 {
    const first = word & 0x07ff;
    const second = (word >> 16) & 0x07ff;
    return bits.signExtend32((first << 12) | (second << 1), 23);
}
