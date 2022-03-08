const std = @import("std");
const bits = @import("bits.zig");
const arm_exec = @import("arm_exec.zig");
const arm_state = @import("arm_state.zig");
usingnamespace @import("arm_text_types.zig");
usingnamespace @import("arm_text_arm_format.zig");
usingnamespace @import("arm_text_float_format.zig");
usingnamespace @import("arm_text_coprocessor_format.zig");
usingnamespace @import("arm_text_block_format.zig");
usingnamespace @import("arm_text_parallel_format.zig");
usingnamespace @import("arm_text_multiply_format.zig");
usingnamespace @import("arm_text_transfer_format.zig");
usingnamespace @import("arm_text_data_format.zig");
usingnamespace @import("arm_text_thumb_format.zig");
usingnamespace @import("arm_text_thumb32_format.zig");
usingnamespace @import("arm_text_common_format.zig");

pub fn formatSyncArm(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const base = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (word == 0xf57ff01f) {
        return std.fmt.bufPrint(buf, "clrex", .{}) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00fff) == 0x01900f9f) {
        return std.fmt.bufPrint(buf, "ldrex{} {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00fff) == 0x01d00f9f) {
        return std.fmt.bufPrint(buf, "ldrexb{} {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00fff) == 0x01b00f9f) {
        return std.fmt.bufPrint(buf, "ldrexd{} {}, {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(nextReg(dest)),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00fff) == 0x01f00f9f) {
        return std.fmt.bufPrint(buf, "ldrexh{} {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00ff0) == 0x01800f90) {
        return std.fmt.bufPrint(buf, "strex{} {}, {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(source),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00ff0) == 0x01c00f90) {
        return std.fmt.bufPrint(buf, "strexb{} {}, {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(source),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00ff0) == 0x01a00f90) {
        return std.fmt.bufPrint(buf, "strexd{} {}, {}, {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(source),
            arm_state.regName(nextReg(source)),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00ff0) == 0x01e00f90) {
        return std.fmt.bufPrint(buf, "strexh{} {}, {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(source),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00ff0) == 0x01000090) {
        return std.fmt.bufPrint(buf, "swp{} {}, {}, [{}]", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(source),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "swpb{} {}, {}, [{}]", .{
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(source),
        arm_state.regName(base),
    }) catch error.NoSpaceLeft;
}

pub fn isMiscArmFormat(word: u32) bool {
    return (word & 0x0fff0ff0) == 0x016f0f10 or
        (word & 0x0ff00ff0) == 0x06800fb0 or
        (word & 0x0ff0f0f0) == 0x0780f010 or
        (word & 0x0ff000f0) == 0x07800010;
}

pub fn formatMiscArm(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const target = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const right = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 8) & 0xf));
    const left = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    if ((word & 0x0fff0ff0) == 0x016f0f10) {
        return std.fmt.bufPrint(buf, "clz{} {}, {}", .{
            condName(cond),
            arm_state.regName(target),
            arm_state.regName(left),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00ff0) == 0x06800fb0) {
        return std.fmt.bufPrint(buf, "sel{} {}, {}, {}", .{
            condName(cond),
            arm_state.regName(target),
            arm_state.regName(dest),
            arm_state.regName(left),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff0f0f0) == 0x0780f010) {
        return std.fmt.bufPrint(buf, "usad8{} {}, {}, {}", .{
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "usad8a{} {}, {}, {}, {}", .{
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(left),
        arm_state.regName(right),
        arm_state.regName(target),
    }) catch error.NoSpaceLeft;
}

