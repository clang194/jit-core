const std = @import("std");
const text_types = @import("arm_text_types.zig");
const TextError = text_types.TextError;
const bits = @import("bits.zig");
const arm_exec = @import("arm_exec.zig");
const arm_state = @import("arm_state.zig");
usingnamespace @import("arm_text_types.zig");
usingnamespace @import("arm_text_arm_format.zig");
usingnamespace @import("arm_text_float_format.zig");
usingnamespace @import("arm_text_coprocessor_format.zig");
usingnamespace @import("arm_text_block_format.zig");
usingnamespace @import("arm_text_misc_format.zig");
usingnamespace @import("arm_text_parallel_format.zig");
usingnamespace @import("arm_text_multiply_format.zig");
usingnamespace @import("arm_text_transfer_format.zig");
usingnamespace @import("arm_text_data_format.zig");
usingnamespace @import("arm_text_thumb_format.zig");
usingnamespace @import("arm_text_common_format.zig");

pub fn formatThumb32(buf: []u8, word: u32) TextError![]u8 {
    const first = @intCast(u16, word & 0xffff);
    const second = @intCast(u16, (word >> 16) & 0xffff);
    if ((first & 0xf800) == 0xf000 and (second & 0xf800) == 0xf800) {
        const offset = thumb32Offset(word) + 4;
        return std.fmt.bufPrint(buf, "bl {c}#{}", .{
            signChar(offset),
            abs32(offset),
        }) catch error.NoSpaceLeft;
    }
    if ((first & 0xf800) == 0xf000 and (second & 0xf800) == 0xe800 and (second & 1) == 0) {
        const offset = thumb32Offset(word) + 4;
        return std.fmt.bufPrint(buf, "blx {c}#{}", .{
            signChar(offset),
            abs32(offset),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "unknown #{x}", .{word}) catch error.NoSpaceLeft;
}
