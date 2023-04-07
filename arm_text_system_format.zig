const std = @import("std");
usingnamespace @import("arm_text_types.zig");

pub fn formatArmBarrier(buf: []u8, word: u32) TextError![]u8 {
    const masked = word & 0xfffffff0;
    if (masked == 0xf57ff060) {
        return std.fmt.bufPrint(buf, "isb", .{}) catch error.NoSpaceLeft;
    }
    const name = if (masked == 0xf57ff040) "dsb" else "dmb";
    const option = barrierOption(word & 0xf);
    if (option.len == 0) {
        return std.fmt.bufPrint(buf, "{}", .{name}) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{} {}", .{ name, option }) catch error.NoSpaceLeft;
}

fn barrierOption(value: u32) []const u8 {
    return switch (value) {
        0x2 => "oshst",
        0x3 => "osh",
        0x6 => "nshst",
        0x7 => "nsh",
        0xa => "ishst",
        0xb => "ish",
        0xe => "st",
        0xf => "",
        else => "unknown",
    };
}
