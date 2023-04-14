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

pub fn formatFloatAdd(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vadd{}.f64 d{}, d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vadd{}.f32 s{}, s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatThree(buf: []u8, word: u32, cond: u4, name: []const u8) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "{}{}.f64 d{}, d{}, d{}", .{
            name,
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{}.f32 s{}, s{}, s{}", .{
        name,
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatSub(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vsub{}.f64 d{}, d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vsub{}.f32 s{}, s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMul(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vmul{}.f64 d{}, d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vmul{}.f32 s{}, s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatNegMul(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vnmul{}.f64 d{}, d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vnmul{}.f32 s{}, s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatDiv(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vdiv{}.f64 d{}, d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vdiv{}.f32 s{}, s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveCoreToPairLow(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{}.32 d{}, {}", .{
        condName(cond),
        floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
        arm_state.regName(armReg(word >> 12)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMovePairLowToCore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{}.32 {}, d{}", .{
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        floatPairTextIndex(word >> 16, bits.getBit32(word, 7)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveCoreToWord(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{}.32 s{}, {}", .{
        condName(cond),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
        arm_state.regName(armReg(word >> 12)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveWordToCore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{}.32 {}, s{}", .{
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        floatWordTextIndex(word >> 16, bits.getBit32(word, 7)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveTwoCoreToTwoWord(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const first = floatWordTextIndex(word, bits.getBit32(word, 5));
    return std.fmt.bufPrint(buf, "vmov{} s{}, s{}, {}, {}", .{
        condName(cond),
        first,
        first + 1,
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveTwoWordToTwoCore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const first = floatWordTextIndex(word, bits.getBit32(word, 5));
    return std.fmt.bufPrint(buf, "vmov{} {}, {}, s{}, s{}", .{
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
        first,
        first + 1,
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveTwoCoreToPair(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{} d{}, {}, {}", .{
        condName(cond),
        floatPairTextIndex(word, bits.getBit32(word, 5)),
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMovePairToTwoCore(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "vmov{} {}, {}, d{}", .{
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
        floatPairTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}

pub fn formatFloatMoveReg(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    if (bits.getBit32(word, 8)) {
        return std.fmt.bufPrint(buf, "vmov{}.f64 d{}, d{}", .{
            condName(cond),
            floatPairTextIndex(word >> 12, bits.getBit32(word, 22)),
            floatPairTextIndex(word, bits.getBit32(word, 5)),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "vmov{}.f32 s{}, s{}", .{
        condName(cond),
        floatWordTextIndex(word >> 12, bits.getBit32(word, 22)),
        floatWordTextIndex(word, bits.getBit32(word, 5)),
    }) catch error.NoSpaceLeft;
}
