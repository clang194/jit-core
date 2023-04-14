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
const text_float_convert = @import("arm_text_float_convert_format.zig");
const floatPairTextIndex = text_float_convert.floatPairTextIndex;
const floatWordTextIndex = text_float_convert.floatWordTextIndex;
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

pub fn formatFloatLoad(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const suffix = if (bits.getBit32(word, 23)) "+" else "-";
    const offset = (word & 0xff) << 2;
    const base = armReg(word >> 16);
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vldr{} d{}, [{}, #{}{}]", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            arm_state.regName(base),
            suffix,
            offset,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vldr{} s{}, [{}, #{}{}]", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        arm_state.regName(base),
        suffix,
        offset,
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatStore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const suffix = if (bits.getBit32(word, 23)) "+" else "-";
    const offset = (word & 0xff) << 2;
    const base = armReg(word >> 16);
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vstr{} d{}, [{}, #{}{}]", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            arm_state.regName(base),
            suffix,
            offset,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vstr{} s{}, [{}, #{}{}]", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        arm_state.regName(base),
        suffix,
        offset,
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatStack(buf: []u8, word: u32, cond: u4, name: []const u8) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "{}{} d{}(+{})", .{
            name,
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            (word & 0xff) >> 1,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{} s{}(+{})", .{
        name,
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        word & 0xff,
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatStoreMultiple(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const mode = if (!bits.getBit32(word, 24) and bits.getBit32(word, 23)) "ia" else if (bits.getBit32(word, 24) and !bits.getBit32(word, 23)) "db" else "??";
    const marker = if (bits.getBit32(word, 21)) "!" else "";
    const base = armReg(word >> 16);
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vstm{}{}.f64 {}{}, d{}(+{})", .{
            mode,
            condName(cond),
            arm_state.regName(base),
            marker,
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            (word & 0xff) >> 1,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vstm{}{}.f32 {}{}, s{}(+{})", .{
        mode,
        condName(cond),
        arm_state.regName(base),
        marker,
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        word & 0xff,
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatLoadMultiple(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const mode = if (!bits.getBit32(word, 24) and bits.getBit32(word, 23)) "ia" else if (bits.getBit32(word, 24) and !bits.getBit32(word, 23)) "db" else "??";
    const marker = if (bits.getBit32(word, 21)) "!" else "";
    const base = armReg(word >> 16);
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vldm{}{}.f64 {}{}, d{}(+{})", .{
            mode,
            condName(cond),
            arm_state.regName(base),
            marker,
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            (word & 0xff) >> 1,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vldm{}{}.f32 {}{}, s{}(+{})", .{
        mode,
        condName(cond),
        arm_state.regName(base),
        marker,
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        word & 0xff,
    }) catch error.NoSpaceLeft;
}
