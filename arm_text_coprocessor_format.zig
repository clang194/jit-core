const std = @import("std");
const text_types = @import("arm_text_types.zig");
const TextError = text_types.TextError;
const bits = @import("bits.zig");
const arm_exec = @import("arm_exec.zig");
const arm_state = @import("arm_state.zig");
const text_common = @import("arm_text_common_format.zig");
const condOrTwo = text_common.condOrTwo;
usingnamespace @import("arm_text_types.zig");
usingnamespace @import("arm_text_arm_format.zig");
usingnamespace @import("arm_text_float_format.zig");
usingnamespace @import("arm_text_block_format.zig");
usingnamespace @import("arm_text_misc_format.zig");
usingnamespace @import("arm_text_parallel_format.zig");
usingnamespace @import("arm_text_multiply_format.zig");
usingnamespace @import("arm_text_transfer_format.zig");
usingnamespace @import("arm_text_data_format.zig");
usingnamespace @import("arm_text_thumb_format.zig");
usingnamespace @import("arm_text_thumb32_format.zig");
usingnamespace @import("arm_text_common_format.zig");

pub fn formatCoprocessor(buf: []u8, word: u32) TextError!?[]u8 {
    if ((word & 0xff000010) == 0xfe000000 or (word & 0x0f000010) == 0x0e000000) {
        return formatCoprocCommand(buf, word);
    }

    if ((word & 0xfe100000) == 0xfc100000 or (word & 0x0e100000) == 0x0c100000) {
        return formatCoprocBlock(buf, "ldc", word);
    }

    if ((word & 0xff100010) == 0xfe000010 or (word & 0x0f100010) == 0x0e000010) {
        return formatCoprocWord(buf, "mcr", word);
    }

    if ((word & 0xfff00000) == 0xfc400000 or (word & 0x0ff00000) == 0x0c400000) {
        return formatCoprocPair(buf, "mcrr", word);
    }

    if ((word & 0xff100010) == 0xfe100010 or (word & 0x0f100010) == 0x0e100010) {
        return formatCoprocWord(buf, "mrc", word);
    }

    if ((word & 0xfff00000) == 0xfc500000 or (word & 0x0ff00000) == 0x0c500000) {
        return formatCoprocPair(buf, "mrrc", word);
    }

    if ((word & 0xfe100000) == 0xfc000000 or (word & 0x0e100000) == 0x0c000000) {
        return formatCoprocBlock(buf, "stc", word);
    }

    return null;
}

pub fn formatCoprocCommand(buf: []u8, word: u32) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    return std.fmt.bufPrint(buf, "cdp{} p{}, #{}, {}, {}, {}, #{}", .{
        condOrTwo(cond),
        (word >> 8) & 0xf,
        (word >> 20) & 0xf,
        arm_state.coprocessorRegName(coprocReg(word >> 12)),
        arm_state.coprocessorRegName(coprocReg(word >> 16)),
        arm_state.coprocessorRegName(coprocReg(word)),
        (word >> 5) & 0x7,
    }) catch error.NoSpaceLeft;
}

pub fn formatCoprocWord(buf: []u8, comptime op: []const u8, word: u32) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    return std.fmt.bufPrint(buf, "{}{} p{}, #{}, {}, {}, {}, #{}", .{
        op,
        condOrTwo(cond),
        (word >> 8) & 0xf,
        (word >> 21) & 0x7,
        arm_state.regName(armReg(word >> 12)),
        arm_state.coprocessorRegName(coprocReg(word >> 16)),
        arm_state.coprocessorRegName(coprocReg(word)),
        (word >> 5) & 0x7,
    }) catch error.NoSpaceLeft;
}

pub fn formatCoprocPair(buf: []u8, comptime op: []const u8, word: u32) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    return std.fmt.bufPrint(buf, "{}{} p{}, #{}, {}, {}, {}", .{
        op,
        condOrTwo(cond),
        (word >> 8) & 0xf,
        (word >> 4) & 0xf,
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
        arm_state.coprocessorRegName(coprocReg(word)),
    }) catch error.NoSpaceLeft;
}

pub fn formatCoprocBlock(buf: []u8, comptime op: []const u8, word: u32) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    const pre = bits.getBit32(word, 24);
    const add = bits.getBit32(word, 23);
    const long = bits.getBit32(word, 22);
    const write_back = bits.getBit32(word, 21);
    if (!pre and !add and !long and !write_back) {
        return error.UnknownInstruction;
    }
    const suffix = if (long) "l" else "";
    const offset = (word & 0xff) << 2;
    const sign = if (add) "+" else "-";
    if (pre) {
        return std.fmt.bufPrint(buf, "{}{}{} p{}, {}, [{}, #{}{}]{}", .{
            op,
            suffix,
            condOrTwo(cond),
            (word >> 8) & 0xf,
            arm_state.coprocessorRegName(coprocReg(word >> 12)),
            arm_state.regName(armReg(word >> 16)),
            sign,
            offset,
            if (write_back) "!" else "",
        }) catch error.NoSpaceLeft;
    }
    if (write_back) {
        return std.fmt.bufPrint(buf, "{}{}{} p{}, {}, [{}], #{}{}", .{
            op,
            suffix,
            condOrTwo(cond),
            (word >> 8) & 0xf,
            arm_state.coprocessorRegName(coprocReg(word >> 12)),
            arm_state.regName(armReg(word >> 16)),
            sign,
            offset,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{}{} p{}, {}, [{}], {}", .{
        op,
        suffix,
        condOrTwo(cond),
        (word >> 8) & 0xf,
        arm_state.coprocessorRegName(coprocReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
        word & 0xff,
    }) catch error.NoSpaceLeft;
}

pub fn armReg(value: u32) arm_state.ArmReg {
    return @intToEnum(arm_state.ArmReg, @intCast(u8, value & 0xf));
}

pub fn coprocReg(value: u32) arm_state.CoprocessorReg {
    return @intToEnum(arm_state.CoprocessorReg, @intCast(u4, value & 0xf));
}
