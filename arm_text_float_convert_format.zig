const std = @import("std");
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


pub fn formatFloatAbs(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vabs{}.f64 d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vabs{}.f32 s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatNeg(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vneg{}.f64 d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vneg{}.f32 s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatSqrt(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vsqrt{}.f64 d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vsqrt{}.f32 s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatConvertWidth(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vcvt{}.f32.f64 s{}, d{}", .{
            condName(cond),
            floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vcvt{}.f64.f32 d{}, s{}", .{
        condName(cond),
        floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatConvertIntToFloat(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const int_type = if (bits.getBit32(word, 7)) "s32" else "u32";
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vcvt{}.f64.{} d{}, s{}", .{
            condName(cond),
            int_type,
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatWordTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vcvt{}.f32.{} s{}, s{}", .{
        condName(cond),
        int_type,
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatConvertToInt(buf: []u8, word: u32, cond: u4, int_type: []const u8) TextError![]u8 {
    const rounded = if (bits.getBit32(word, 7)) "" else "r";
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vcvt{}{}.{}.f64 s{}, d{}", .{
            rounded,
            condName(cond),
            int_type,
            floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vcvt{}{}.{}.f32 s{}, s{}", .{
        rounded,
        condName(cond),
        int_type,
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatCompare(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const op = if (bits.getBit32(word, 7)) "vcmpe" else "vcmp";
    const zero = (word & 0x0fbf0e7f) == 0x0eb50a40;
    if (bits.getBit32(word, 8)) {
        if (zero) {
            return std.fmt.bufPrint(buf, "{}{}.f64 d{}, #0.0", .{
                op,
                condName(cond),
                floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            }) catch error.NoSpaceLeft;
        }
        return std.fmt.bufPrint(buf, "{}{}.f64 d{}, d{}", .{
            op,
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    if (zero) {
        return std.fmt.bufPrint(buf, "{}{}.f32 s{}, #0.0", .{
            op,
            condName(cond),
            floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{}.f32 s{}, s{}", .{
        op,
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatStatusWrite(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const source = armReg(word >> 12);
    return std.fmt.bufPrint(buf, "vmsr{} fpscr, {}", .{
        condName(cond),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatStatusRead(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const dest = armReg(word >> 12);
    if (dest == .pc) {
        return std.fmt.bufPrint(buf, "vmrs{} apsr_nzcv, fpscr", .{condName(cond)}) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vmrs{} {}, fpscr", .{
        condName(cond),
        arm_state.regName(dest),
    }) catch error.NoSpaceLeft;
}

pub fn floatWordTextIndex(value: u32, high: bool) u32 {
    return ((value & 0xf) << 1) | @as(u32, @boolToInt(high));
}

pub fn floatPairTextIndex(value: u32, high: bool) u32 {
    return (value & 0xf) | (@as(u32, @boolToInt(high)) << 4);
}

