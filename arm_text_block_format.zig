const std = @import("std");
const bits = @import("bits.zig");
const arm_exec = @import("arm_exec.zig");
const arm_state = @import("arm_state.zig");
usingnamespace @import("arm_text_types.zig");
usingnamespace @import("arm_text_arm_format.zig");
usingnamespace @import("arm_text_float_format.zig");
usingnamespace @import("arm_text_coprocessor_format.zig");
usingnamespace @import("arm_text_misc_format.zig");
usingnamespace @import("arm_text_parallel_format.zig");
usingnamespace @import("arm_text_multiply_format.zig");
usingnamespace @import("arm_text_transfer_format.zig");
usingnamespace @import("arm_text_data_format.zig");
usingnamespace @import("arm_text_thumb_format.zig");
usingnamespace @import("arm_text_thumb32_format.zig");
usingnamespace @import("arm_text_common_format.zig");

pub fn isArmLoadMultiple(word: u32) bool {
    return (word & 0x0e500000) == 0x08100000 and arm_state.conditionFromNibble(@intCast(u4, word >> 28)) != null;
}

pub fn isArmStoreMultiple(word: u32) bool {
    return (word & 0x0e500000) == 0x08000000 and arm_state.conditionFromNibble(@intCast(u4, word >> 28)) != null;
}

pub fn formatArmLoadMultiple(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    var used: usize = 0;
    const op = if (bits.getBit32(word, 24))
        if (bits.getBit32(word, 23)) "ldmib" else "ldmdb"
    else
        if (bits.getBit32(word, 23)) "ldm" else "ldmda";
    try appendText(buf, &used, op);
    try appendText(buf, &used, condName(cond));
    try appendText(buf, &used, " ");
    try appendText(buf, &used, arm_state.regName(armReg(word >> 16)));
    if (bits.getBit32(word, 21)) {
        try appendText(buf, &used, "!");
    }
    try appendText(buf, &used, ", {");
    try appendRegList(buf, &used, @intCast(u16, word & 0xffff));
    try appendText(buf, &used, "}");
    return buf[0..used];
}

pub fn formatArmStoreMultiple(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    var used: usize = 0;
    const op = if (bits.getBit32(word, 24))
        if (bits.getBit32(word, 23)) "stmib" else "stmdb"
    else
        if (bits.getBit32(word, 23)) "stm" else "stmda";
    try appendText(buf, &used, op);
    try appendText(buf, &used, condName(cond));
    try appendText(buf, &used, " ");
    try appendText(buf, &used, arm_state.regName(armReg(word >> 16)));
    if (bits.getBit32(word, 21)) {
        try appendText(buf, &used, "!");
    }
    try appendText(buf, &used, ", {");
    try appendRegList(buf, &used, @intCast(u16, word & 0xffff));
    try appendText(buf, &used, "}");
    return buf[0..used];
}

pub fn isSyncArmFormat(word: u32) bool {
    return word == 0xf57ff01f or
        (word & 0x0ff00fff) == 0x01900f9f or
        (word & 0x0ff00fff) == 0x01d00f9f or
        (word & 0x0ff00fff) == 0x01b00f9f or
        (word & 0x0ff00fff) == 0x01f00f9f or
        (word & 0x0ff00ff0) == 0x01800f90 or
        (word & 0x0ff00ff0) == 0x01c00f90 or
        (word & 0x0ff00ff0) == 0x01a00f90 or
        (word & 0x0ff00ff0) == 0x01e00f90 or
        (word & 0x0ff00ff0) == 0x01000090 or
        (word & 0x0ff00ff0) == 0x01400090;
}

