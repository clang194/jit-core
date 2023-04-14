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
usingnamespace @import("arm_text_thumb32_format.zig");

pub fn formatThumbShiftImm(buf: []u8, comptime op: []const u8, word: u16, zero_is_thirty_two: bool) TextError![]u8 {
    const raw_amount = @intCast(u8, (word >> 6) & 0x1f);
    const amount = if (zero_is_thirty_two and raw_amount == 0) 32 else raw_amount;
    const source = arm_state.lowReg(word >> 3);
    const dest = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, {}, #{}", .{
        op,
        arm_state.regName(dest),
        arm_state.regName(source),
        amount,
    }) catch error.NoSpaceLeft;
}

pub fn formatThumbBitReg(buf: []u8, comptime op: []const u8, word: u16) TextError![]u8 {
    const source = arm_state.lowReg(word >> 3);
    const dest = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, {}", .{
        op,
        arm_state.regName(dest),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

pub fn formatThumbShiftReg(buf: []u8, comptime op: []const u8, word: u16) TextError![]u8 {
    const source = arm_state.lowReg(word >> 3);
    const dest = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, {}", .{
        op,
        arm_state.regName(dest),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

pub fn formatThumbTransferReg(buf: []u8, comptime op: []const u8, word: u16) TextError![]u8 {
    const offset = arm_state.lowReg(word >> 6);
    const base = arm_state.lowReg(word >> 3);
    const data = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, [{}, {}]", .{
        op,
        arm_state.regName(data),
        arm_state.regName(base),
        arm_state.regName(offset),
    }) catch error.NoSpaceLeft;
}

pub fn formatThumbTransferImm(buf: []u8, comptime op: []const u8, word: u16, comptime scale: u5) TextError![]u8 {
    const offset = @as(u32, (word >> 6) & 0x1f) << scale;
    const base = arm_state.lowReg(word >> 3);
    const data = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, [{}, #{}]", .{
        op,
        arm_state.regName(data),
        arm_state.regName(base),
        offset,
    }) catch error.NoSpaceLeft;
}

pub fn formatThumbUnaryReg(buf: []u8, comptime op: []const u8, word: u16) TextError![]u8 {
    const source = arm_state.lowReg(word >> 3);
    const dest = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, {}", .{
        op,
        arm_state.regName(dest),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

pub fn formatThumbPush(buf: []u8, word: u16) TextError![]u8 {
    var used: usize = 0;
    try appendText(buf, &used, "push {");
    var first = true;
    var index: u8 = 0;
    while (index < 8) : (index += 1) {
        if ((word & (@as(u16, 1) << @intCast(u4, index))) != 0) {
            if (!first) {
                try appendText(buf, &used, ", ");
            }
            try appendText(buf, &used, arm_state.regName(@intToEnum(arm_state.ArmReg, index)));
            first = false;
        }
    }
    if ((word & 0x0100) != 0) {
        if (!first) {
            try appendText(buf, &used, ", ");
        }
        try appendText(buf, &used, arm_state.regName(.lr));
    }
    try appendText(buf, &used, "}");
    return buf[0..used];
}

pub fn formatThumbPop(buf: []u8, word: u16) TextError![]u8 {
    var used: usize = 0;
    try appendText(buf, &used, "pop {");
    var first = true;
    var index: u8 = 0;
    while (index < 8) : (index += 1) {
        if ((word & (@as(u16, 1) << @intCast(u4, index))) != 0) {
            if (!first) {
                try appendText(buf, &used, ", ");
            }
            try appendText(buf, &used, arm_state.regName(@intToEnum(arm_state.ArmReg, index)));
            first = false;
        }
    }
    if ((word & 0x0100) != 0) {
        if (!first) {
            try appendText(buf, &used, ", ");
        }
        try appendText(buf, &used, arm_state.regName(.pc));
    }
    try appendText(buf, &used, "}");
    return buf[0..used];
}

pub fn formatThumbMultiple(buf: []u8, comptime op: []const u8, base: arm_state.ArmReg, mask: u8, write_back: bool) TextError![]u8 {
    var used: usize = 0;
    try appendText(buf, &used, op);
    try appendText(buf, &used, " ");
    try appendText(buf, &used, arm_state.regName(base));
    if (write_back) {
        try appendText(buf, &used, "!");
    }
    try appendText(buf, &used, ", {");
    try appendRegList(buf, &used, mask);
    try appendText(buf, &used, "}");
    return buf[0..used];
}

pub fn appendRegList(buf: []u8, used: *usize, mask: u16) TextError!void {
    var first = true;
    var index: u5 = 0;
    while (index < 16) : (index += 1) {
        if ((mask & (@as(u16, 1) << index)) != 0) {
            if (!first) {
                try appendText(buf, used, ", ");
            }
            try appendText(buf, used, arm_state.regName(@intToEnum(arm_state.ArmReg, @intCast(u8, index))));
            first = false;
        }
    }
}

pub fn appendText(buf: []u8, used: *usize, text: []const u8) TextError!void {
    if (used.* + text.len > buf.len) {
        return error.NoSpaceLeft;
    }
    std.mem.copy(u8, buf[used.* .. used.* + text.len], text);
    used.* += text.len;
}

pub fn formatBranchImmediate(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const link = bits.getBit32(word, 24);
    const imm = word & 0x00ffffff;
    const offset = bits.signExtend32(imm << 2, 26) + 8;
    const op: []const u8 = if (link) "bl" else "b";
    return std.fmt.bufPrint(buf, "{}{} {c}#{}", .{
        op,
        condName(cond),
        signChar(offset),
        abs32(offset),
    }) catch error.NoSpaceLeft;
}

pub fn formatBranchExchangeImmediate(buf: []u8, word: u32) TextError![]u8 {
    const high = @as(u32, @boolToInt(bits.getBit32(word, 24)));
    const imm = word & 0x00ffffff;
    const offset = bits.signExtend32((imm << 2) | (high << 1), 26) + 8;
    return std.fmt.bufPrint(buf, "blx {c}#{}", .{ signChar(offset), abs32(offset) }) catch error.NoSpaceLeft;
}

pub fn thumb32Offset(word: u32) i32 {
    const first = word & 0x07ff;
    const second = (word >> 16) & 0x07ff;
    return bits.signExtend32((first << 12) | (second << 1), 23);
}

pub fn condName(cond: u4) []const u8 {
    if (arm_state.conditionFromNibble(cond)) |code| {
        return arm_state.conditionSuffix(code);
    }
    return "";
}

pub fn condOrTwo(cond: u4) []const u8 {
    if (cond == 0xf) {
        return "2";
    }
    return condName(cond);
}

pub fn signChar(value: i32) u8 {
    if (value < 0) {
        return '-';
    }
    return '+';
}

pub fn abs32(value: i32) u32 {
    if (value < 0) {
        return @intCast(u32, -value);
    }
    return @intCast(u32, value);
}
