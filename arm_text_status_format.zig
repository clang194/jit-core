const std = @import("std");
const text_coprocessor = @import("arm_text_coprocessor_format.zig");
const armReg = text_coprocessor.armReg;
const text_common = @import("arm_text_common_format.zig");
const condName = text_common.condName;
const text_types = @import("arm_text_types.zig");
const TextError = text_types.TextError;
const bits = @import("bits.zig");
const arm_exec = @import("arm_exec.zig");
const arm_state = @import("arm_state.zig");
usingnamespace @import("arm_text_types.zig");
usingnamespace @import("arm_text_arm_format.zig");
usingnamespace @import("arm_text_coprocessor_format.zig");
usingnamespace @import("arm_text_block_format.zig");
usingnamespace @import("arm_text_misc_format.zig");
usingnamespace @import("arm_text_parallel_format.zig");
usingnamespace @import("arm_text_multiply_format.zig");
usingnamespace @import("arm_text_transfer_format.zig");
usingnamespace @import("arm_text_data_format.zig");
usingnamespace @import("arm_text_thumb_format.zig");
usingnamespace @import("arm_text_thumb32_format.zig");
usingnamespace @import("arm_text_common_format.zig");

pub fn statusMaskName(word: u32) TextError![]const u8 {
    return switch ((word >> 16) & 0xf) {
        0x1 => "c",
        0x2 => "x",
        0x3 => "cx",
        0x4 => "s",
        0x5 => "cs",
        0x6 => "xs",
        0x7 => "cxs",
        0x8 => "f",
        0x9 => "cf",
        0xa => "xf",
        0xb => "cxf",
        0xc => "sf",
        0xd => "csf",
        0xe => "xsf",
        0xf => "cxsf",
        else => error.UnknownInstruction,
    };
}

pub fn formatStatusRead(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const dest = armReg(word >> 12);
    return std.fmt.bufPrint(buf, "mrs{} {}, apsr", .{
        condName(cond),
        arm_state.regName(dest),
    }) catch error.NoSpaceLeft;
}

pub fn formatStatusWriteImmediate(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "msr{} cpsr_{}, #{}", .{
        condName(cond),
        try statusMaskName(word),
        arm_exec.expandArmImmediate(@intCast(u8, (word >> 8) & 0xf), @intCast(u8, word & 0xff)),
    }) catch error.NoSpaceLeft;
}

pub fn formatStatusWriteRegister(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const source = armReg(word);
    return std.fmt.bufPrint(buf, "msr{} cpsr_{}, {}", .{
        condName(cond),
        try statusMaskName(word),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}
