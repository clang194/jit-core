const std = @import("std");
const arm_state = @import("arm_state.zig");
usingnamespace @import("arm_text_types.zig");
usingnamespace @import("arm_text_common_format.zig");

pub fn formatArmDivide(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const name = if ((word & 0x00200000) != 0) "udiv" else "sdiv";
    const dest = armRegName(word >> 12);
    const right = armRegName(word >> 8);
    const left = armRegName(word);
    return std.fmt.bufPrint(buf, "{}{} {}, {}, {}", .{ name, condName(cond), dest, left, right }) catch error.NoSpaceLeft;
}

fn armRegName(value: u32) []const u8 {
    const reg = @intToEnum(arm_state.ArmReg, @intCast(u8, value & 0xf));
    return arm_state.regName(reg);
}
