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
usingnamespace @import("arm_text_multiply_format.zig");
usingnamespace @import("arm_text_data_format.zig");
usingnamespace @import("arm_text_thumb_format.zig");
usingnamespace @import("arm_text_thumb32_format.zig");
usingnamespace @import("arm_text_common_format.zig");

pub fn formatArmTransferWord(buf: []u8, comptime op: []const u8, word: u32) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    const pre_index = bits.getBit32(word, 24);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const base = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const bang: []const u8 = if (writeback) "!" else "";
    var offset_buf: [48]u8 = undefined;
    const offset = try formatArmLoadOffset(offset_buf[0..], word);

    if (pre_index) {
        if (offset.len == 0) {
            return std.fmt.bufPrint(buf, "{}{} {}, [{}]{}", .{
                op,
                condName(cond),
                arm_state.regName(dest),
                arm_state.regName(base),
                bang,
            }) catch error.NoSpaceLeft;
        }
        return std.fmt.bufPrint(buf, "{}{} {}, [{}, {}]{}", .{
            op,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
            offset,
            bang,
        }) catch error.NoSpaceLeft;
    }

    if (offset.len == 0) {
        return std.fmt.bufPrint(buf, "{}{} {}, [{}], #0", .{
            op,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{} {}, [{}], {}", .{
        op,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(base),
        offset,
    }) catch error.NoSpaceLeft;
}

pub fn formatArmLoadOffset(buf: []u8, word: u32) TextError![]u8 {
    const increase = bits.getBit32(word, 23);
    if (!bits.getBit32(word, 25)) {
        const offset = word & 0xfff;
        if (offset == 0) {
            return buf[0..0];
        }
        if (increase) {
            return std.fmt.bufPrint(buf, "#+{}", .{offset}) catch error.NoSpaceLeft;
        }
        return std.fmt.bufPrint(buf, "#-{}", .{offset}) catch error.NoSpaceLeft;
    }

    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const mode = @intCast(u2, (word >> 5) & 0x3);
    const amount = @intCast(u8, (word >> 7) & 0x1f);
    const prefix: []const u8 = if (increase) "+" else "-";
    if (mode == 0 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}{}", .{ prefix, arm_state.regName(source) }) catch error.NoSpaceLeft;
    }
    if (mode == 1 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}{}, lsr #32", .{ prefix, arm_state.regName(source) }) catch error.NoSpaceLeft;
    }
    if (mode == 2 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}{}, asr #32", .{ prefix, arm_state.regName(source) }) catch error.NoSpaceLeft;
    }
    if (mode == 3 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}{}, rrx", .{ prefix, arm_state.regName(source) }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{}, {} #{}", .{
        prefix,
        arm_state.regName(source),
        shiftName(mode),
        amount,
    }) catch error.NoSpaceLeft;
}

pub fn formatArmTransferHalf(buf: []u8, comptime op: []const u8, word: u32) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    const pre_index = bits.getBit32(word, 24);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const base = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const bang: []const u8 = if (writeback) "!" else "";
    var offset_buf: [48]u8 = undefined;
    const offset = try formatArmHalfOffset(offset_buf[0..], word);

    if (pre_index) {
        if (offset.len == 0) {
            return std.fmt.bufPrint(buf, "{}{} {}, [{}]{}", .{
                op,
                condName(cond),
                arm_state.regName(dest),
                arm_state.regName(base),
                bang,
            }) catch error.NoSpaceLeft;
        }
        return std.fmt.bufPrint(buf, "{}{} {}, [{}, {}]{}", .{
            op,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
            offset,
            bang,
        }) catch error.NoSpaceLeft;
    }

    if (offset.len == 0) {
        return std.fmt.bufPrint(buf, "{}{} {}, [{}], #0", .{
            op,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{} {}, [{}], {}", .{
        op,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(base),
        offset,
    }) catch error.NoSpaceLeft;
}

pub fn formatArmHalfOffset(buf: []u8, word: u32) TextError![]u8 {
    const increase = bits.getBit32(word, 23);
    if (bits.getBit32(word, 22)) {
        const offset = ((word >> 4) & 0xf0) | (word & 0xf);
        if (offset == 0) {
            return buf[0..0];
        }
        if (increase) {
            return std.fmt.bufPrint(buf, "#+{}", .{offset}) catch error.NoSpaceLeft;
        }
        return std.fmt.bufPrint(buf, "#-{}", .{offset}) catch error.NoSpaceLeft;
    }

    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    if (increase) {
        return std.fmt.bufPrint(buf, "+{}", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "-{}", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
}

pub fn formatArmTransferDouble(buf: []u8, comptime op: []const u8, word: u32) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    const pre_index = bits.getBit32(word, 24);
    const writeback = !pre_index or bits.getBit32(word, 21);
    const first = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const base = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const bang: []const u8 = if (writeback) "!" else "";
    var offset_buf: [48]u8 = undefined;
    const offset = try formatArmHalfOffset(offset_buf[0..], word);

    if (pre_index) {
        if (offset.len == 0) {
            return std.fmt.bufPrint(buf, "{}{} {}, {}, [{}]{}", .{
                op,
                condName(cond),
                arm_state.regName(first),
                arm_state.regName(nextReg(first)),
                arm_state.regName(base),
                bang,
            }) catch error.NoSpaceLeft;
        }
        return std.fmt.bufPrint(buf, "{}{} {}, {}, [{}, {}]{}", .{
            op,
            condName(cond),
            arm_state.regName(first),
            arm_state.regName(nextReg(first)),
            arm_state.regName(base),
            offset,
            bang,
        }) catch error.NoSpaceLeft;
    }

    if (offset.len == 0) {
        return std.fmt.bufPrint(buf, "{}{} {}, {}, [{}], #0", .{
            op,
            condName(cond),
            arm_state.regName(first),
            arm_state.regName(nextReg(first)),
            arm_state.regName(base),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{} {}, {}, [{}], {}", .{
        op,
        condName(cond),
        arm_state.regName(first),
        arm_state.regName(nextReg(first)),
        arm_state.regName(base),
        offset,
    }) catch error.NoSpaceLeft;
}

pub fn nextReg(reg: arm_state.ArmReg) arm_state.ArmReg {
    const next = @enumToInt(reg) + 1;
    if (next >= 15) {
        return .pc;
    }
    return @intToEnum(arm_state.ArmReg, @intCast(u8, next));
}

