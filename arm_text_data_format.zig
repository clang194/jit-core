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
usingnamespace @import("arm_text_thumb_format.zig");
usingnamespace @import("arm_text_thumb32_format.zig");
usingnamespace @import("arm_text_common_format.zig");

pub fn formatArmData(buf: []u8, word: u32) TextError![]u8 {
    const op = @intCast(u4, (word >> 21) & 0xf);
    const name = dataName(op) orelse return error.UnknownInstruction;
    const cond = @intCast(u4, word >> 28);
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const base = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    var rhs_buf: [48]u8 = undefined;
    const rhs = try formatArmOperand2(rhs_buf[0..], word);

    if (op >= 0x8 and op <= 0xb) {
        return std.fmt.bufPrint(buf, "{}{} {}, {}", .{
            name,
            condName(cond),
            arm_state.regName(base),
            rhs,
        }) catch error.NoSpaceLeft;
    }

    const flags = if (bits.getBit32(word, 20)) "s" else "";
    if (op == 0xd or op == 0xf) {
        return std.fmt.bufPrint(buf, "{}{}{} {}, {}", .{
            name,
            condName(cond),
            flags,
            arm_state.regName(dest),
            rhs,
        }) catch error.NoSpaceLeft;
    }

    return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}", .{
        name,
        condName(cond),
        flags,
        arm_state.regName(dest),
        arm_state.regName(base),
        rhs,
    }) catch error.NoSpaceLeft;
}

pub fn formatArmOperand2(buf: []u8, word: u32) TextError![]u8 {
    if (bits.getBit32(word, 25)) {
        const rotate = @intCast(u8, (word >> 8) & 0xf);
        const imm = @intCast(u8, word & 0xff);
        return std.fmt.bufPrint(buf, "#{}", .{arm_exec.expandArmImmediate(rotate, imm)}) catch error.NoSpaceLeft;
    }

    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const mode = @intCast(u2, (word >> 5) & 0x3);
    if (bits.getBit32(word, 4)) {
        const amount = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 8) & 0xf));
        return std.fmt.bufPrint(buf, "{}, {} {}", .{
            arm_state.regName(source),
            shiftName(mode),
            arm_state.regName(amount),
        }) catch error.NoSpaceLeft;
    }

    const amount = @intCast(u8, (word >> 7) & 0x1f);
    if (mode == 0 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    if (mode == 1 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}, lsr #32", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    if (mode == 2 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}, asr #32", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    if (mode == 3 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}, rrx", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}, {} #{}", .{
        arm_state.regName(source),
        shiftName(mode),
        amount,
    }) catch error.NoSpaceLeft;
}

pub fn dataName(op: u4) ?[]const u8 {
    return switch (op) {
        0x0 => "and",
        0x1 => "eor",
        0x2 => "sub",
        0x3 => "rsb",
        0x4 => "add",
        0x5 => "adc",
        0x6 => "sbc",
        0x7 => "rsc",
        0x8 => "tst",
        0x9 => "teq",
        0xa => "cmp",
        0xb => "cmn",
        0xc => "orr",
        0xd => "mov",
        0xe => "bic",
        0xf => "mvn",
    };
}

pub fn shiftName(mode: u2) []const u8 {
    return switch (mode) {
        0 => "lsl",
        1 => "lsr",
        2 => "asr",
        3 => "ror",
    };
}

pub fn formatArmUnaryReg(buf: []u8, comptime op: []const u8, word: u32, cond: u4) TextError![]u8 {
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    return std.fmt.bufPrint(buf, "{}{} {}, {}", .{
        op,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}
