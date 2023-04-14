const std = @import("std");
const text_types = @import("arm_text_types.zig");
const TextError = text_types.TextError;
const arm_state = @import("arm_state.zig");
usingnamespace @import("arm_text_types.zig");

pub fn formatArmCrc(buf: []u8, word: u32, alt: bool) TextError![]u8 {
    const size = @intCast(u2, (word >> 21) & 3);
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const acc = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const data_reg = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const name = if (alt) "crc32c" else "crc32";
    return std.fmt.bufPrint(buf, "{}{} {}, {}, {}", .{
        name,
        crcSizeName(size),
        arm_state.regName(dest),
        arm_state.regName(acc),
        arm_state.regName(data_reg),
    }) catch error.NoSpaceLeft;
}

fn crcSizeName(size: u2) []const u8 {
    return switch (size) {
        0 => "b",
        1 => "h",
        2 => "w",
        3 => "invalid",
    };
}
