const std = @import("std");
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
usingnamespace @import("arm_text_transfer_format.zig");
usingnamespace @import("arm_text_data_format.zig");
usingnamespace @import("arm_text_thumb_format.zig");
usingnamespace @import("arm_text_thumb32_format.zig");
usingnamespace @import("arm_text_common_format.zig");

pub const MultiplyText = struct {
    name: []const u8,
    long: bool,
    addend: bool,
    flags: bool,
};

pub fn formatArmMultiply(buf: []u8, word: u32) TextError![]u8 {
    const info = multiplyText(word) orelse return error.UnknownInstruction;
    const cond = @intCast(u4, word >> 28);
    const flags = if (info.flags and bits.getBit32(word, 20)) "s" else "";
    const dest_hi = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const dest_lo = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const right = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 8) & 0xf));
    const left = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));

    if (info.long) {
        return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}, {}", .{
            info.name,
            condName(cond),
            flags,
            arm_state.regName(dest_lo),
            arm_state.regName(dest_hi),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }

    if (info.addend) {
        return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}, {}", .{
            info.name,
            condName(cond),
            flags,
            arm_state.regName(dest_hi),
            arm_state.regName(left),
            arm_state.regName(right),
            arm_state.regName(dest_lo),
        }) catch error.NoSpaceLeft;
    }

    return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}", .{
        info.name,
        condName(cond),
        flags,
        arm_state.regName(dest_hi),
        arm_state.regName(left),
        arm_state.regName(right),
    }) catch error.NoSpaceLeft;
}

pub fn multiplyText(word: u32) ?MultiplyText {
    if (arm_state.conditionFromNibble(@intCast(u4, word >> 28)) == null) {
        return null;
    }
    if ((word & 0x0fe0f0f0) == 0x00000090) {
        return MultiplyText{ .name = "mul", .long = false, .addend = false, .flags = true };
    }
    if ((word & 0x0fe000f0) == 0x00200090) {
        return MultiplyText{ .name = "mla", .long = false, .addend = true, .flags = true };
    }
    if ((word & 0x0fe000f0) == 0x00800090) {
        return MultiplyText{ .name = "umull", .long = true, .addend = false, .flags = true };
    }
    if ((word & 0x0fe000f0) == 0x00a00090) {
        return MultiplyText{ .name = "umlal", .long = true, .addend = false, .flags = true };
    }
    if ((word & 0x0ff000f0) == 0x00400090) {
        return MultiplyText{ .name = "umaal", .long = true, .addend = false, .flags = false };
    }
    if ((word & 0x0fe000f0) == 0x00c00090) {
        return MultiplyText{ .name = "smull", .long = true, .addend = false, .flags = true };
    }
    if ((word & 0x0fe000f0) == 0x00e00090) {
        return MultiplyText{ .name = "smlal", .long = true, .addend = false, .flags = true };
    }
    return null;
}

