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
usingnamespace @import("arm_text_transfer_format.zig");
usingnamespace @import("arm_text_data_format.zig");
usingnamespace @import("arm_text_thumb32_format.zig");
usingnamespace @import("arm_text_common_format.zig");

pub fn formatThumb16(buf: []u8, word: u16) TextError![]u8 {
    if ((word & 0xf800) == 0x0000) {
        return formatThumbShiftImm(buf, "lsls", word, false);
    }
    if ((word & 0xf800) == 0x0800) {
        return formatThumbShiftImm(buf, "lsrs", word, true);
    }
    if ((word & 0xf800) == 0x1000) {
        return formatThumbShiftImm(buf, "asrs", word, true);
    }
    if ((word & 0xfe00) == 0x1800) {
        const addend = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "adds {}, {}, {}", .{
            arm_state.regName(dest),
            arm_state.regName(base),
            arm_state.regName(addend),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xfe00) == 0x1a00) {
        const subtrahend = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "subs {}, {}, {}", .{
            arm_state.regName(dest),
            arm_state.regName(base),
            arm_state.regName(subtrahend),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xfe00) == 0x1c00) {
        const amount = @intCast(u8, (word >> 6) & 7);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "adds {}, {}, #{}", .{
            arm_state.regName(dest),
            arm_state.regName(base),
            amount,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xfe00) == 0x1e00) {
        const amount = @intCast(u8, (word >> 6) & 7);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "subs {}, {}, #{}", .{
            arm_state.regName(dest),
            arm_state.regName(base),
            amount,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x2000) {
        const dest = arm_state.lowReg(word >> 8);
        const imm = @intCast(u8, word & 0xff);
        return std.fmt.bufPrint(buf, "movs {}, #{}", .{
            arm_state.regName(dest),
            imm,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x2800) {
        const source = arm_state.lowReg(word >> 8);
        const imm = @intCast(u8, word & 0xff);
        return std.fmt.bufPrint(buf, "cmp {}, #{}", .{
            arm_state.regName(source),
            imm,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x3000) {
        const dest = arm_state.lowReg(word >> 8);
        const imm = @intCast(u8, word & 0xff);
        return std.fmt.bufPrint(buf, "adds {}, #{}", .{
            arm_state.regName(dest),
            imm,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x3800) {
        const dest = arm_state.lowReg(word >> 8);
        const imm = @intCast(u8, word & 0xff);
        return std.fmt.bufPrint(buf, "subs {}, #{}", .{
            arm_state.regName(dest),
            imm,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xffc0) == 0x4000) {
        return formatThumbBitReg(buf, "ands", word);
    }
    if ((word & 0xffc0) == 0x4040) {
        return formatThumbBitReg(buf, "eors", word);
    }
    if ((word & 0xffc0) == 0x4080) {
        return formatThumbShiftReg(buf, "lsls", word);
    }
    if ((word & 0xffc0) == 0x40c0) {
        return formatThumbShiftReg(buf, "lsrs", word);
    }
    if ((word & 0xffc0) == 0x4100) {
        return formatThumbShiftReg(buf, "asrs", word);
    }
    if ((word & 0xffc0) == 0x4140) {
        return formatThumbBitReg(buf, "adcs", word);
    }
    if ((word & 0xffc0) == 0x4180) {
        return formatThumbBitReg(buf, "sbcs", word);
    }
    if ((word & 0xffc0) == 0x41c0) {
        return formatThumbBitReg(buf, "rors", word);
    }
    if ((word & 0xffc0) == 0x4200) {
        return formatThumbBitReg(buf, "tst", word);
    }
    if ((word & 0xffc0) == 0x4240) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "rsbs {}, {}, #0", .{
            arm_state.regName(dest),
            arm_state.regName(source),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xffc0) == 0x4280) {
        return formatThumbBitReg(buf, "cmp", word);
    }
    if ((word & 0xffc0) == 0x42c0) {
        return formatThumbBitReg(buf, "cmn", word);
    }
    if ((word & 0xffc0) == 0x4300) {
        return formatThumbBitReg(buf, "orrs", word);
    }
    if ((word & 0xffc0) == 0x4380) {
        return formatThumbBitReg(buf, "bics", word);
    }
    if ((word & 0xffc0) == 0x43c0) {
        return formatThumbBitReg(buf, "mvns", word);
    }
    if ((word & 0xff00) == 0x4400) {
        const dest = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const addend = arm_state.reg4(word >> 3);
        return std.fmt.bufPrint(buf, "add {}, {}", .{
            arm_state.regName(dest),
            arm_state.regName(addend),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xff00) == 0x4500) {
        const left = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const right = arm_state.reg4(word >> 3);
        return std.fmt.bufPrint(buf, "cmp {}, {}", .{
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xff00) == 0x4600) {
        const dest = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const source = arm_state.reg4(word >> 3);
        return std.fmt.bufPrint(buf, "mov {}, {}", .{
            arm_state.regName(dest),
            arm_state.regName(source),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xff87) == 0x4700) {
        const source = arm_state.reg4(word >> 3);
        return std.fmt.bufPrint(buf, "bx {}", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    if ((word & 0xff87) == 0x4780) {
        const source = arm_state.reg4(word >> 3);
        return std.fmt.bufPrint(buf, "blx {}", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x4800) {
        const dest = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        return std.fmt.bufPrint(buf, "ldr {}, [pc, #{}]", .{
            arm_state.regName(dest),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xfe00) == 0x5000) {
        return formatThumbTransferReg(buf, "str", word);
    }
    if ((word & 0xfe00) == 0x5200) {
        return formatThumbTransferReg(buf, "strh", word);
    }
    if ((word & 0xfe00) == 0x5400) {
        return formatThumbTransferReg(buf, "strb", word);
    }
    if ((word & 0xfe00) == 0x5600) {
        return formatThumbTransferReg(buf, "ldrsb", word);
    }
    if ((word & 0xfe00) == 0x5800) {
        return formatThumbTransferReg(buf, "ldr", word);
    }
    if ((word & 0xfe00) == 0x5a00) {
        return formatThumbTransferReg(buf, "ldrh", word);
    }
    if ((word & 0xfe00) == 0x5c00) {
        return formatThumbTransferReg(buf, "ldrb", word);
    }
    if ((word & 0xfe00) == 0x5e00) {
        return formatThumbTransferReg(buf, "ldrsh", word);
    }
    if ((word & 0xf800) == 0x6000) {
        return formatThumbTransferImm(buf, "str", word, 2);
    }
    if ((word & 0xf800) == 0x6800) {
        const offset = @as(u32, (word >> 6) & 0x1f) << 2;
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "ldr {}, [{}, #{}]", .{
            arm_state.regName(dest),
            arm_state.regName(base),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x7000) {
        return formatThumbTransferImm(buf, "strb", word, 0);
    }
    if ((word & 0xf800) == 0x7800) {
        return formatThumbTransferImm(buf, "ldrb", word, 0);
    }
    if ((word & 0xf800) == 0x8000) {
        const offset = @as(u32, (word >> 6) & 0x1f) << 1;
        const base = arm_state.lowReg(word >> 3);
        const data = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "strh {}, [{}, #{}]", .{
            arm_state.regName(data),
            arm_state.regName(base),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x8800) {
        const offset = @as(u32, (word >> 6) & 0x1f) << 1;
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        return std.fmt.bufPrint(buf, "ldrh {}, [{}, #{}]", .{
            arm_state.regName(dest),
            arm_state.regName(base),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x9000) {
        const data = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        return std.fmt.bufPrint(buf, "str {}, [sp, #{}]", .{
            arm_state.regName(data),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0x9800) {
        const dest = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        return std.fmt.bufPrint(buf, "ldr {}, [sp, #{}]", .{
            arm_state.regName(dest),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0xa000) {
        const dest = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        return std.fmt.bufPrint(buf, "adr {}, +#{}", .{
            arm_state.regName(dest),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0xa800) {
        const dest = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        return std.fmt.bufPrint(buf, "add {}, sp, #{}", .{
            arm_state.regName(dest),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xff80) == 0xb000) {
        const offset = @as(u32, word & 0x7f) << 2;
        return std.fmt.bufPrint(buf, "add sp, sp, #{}", .{offset}) catch error.NoSpaceLeft;
    }
    if ((word & 0xff80) == 0xb080) {
        const offset = @as(u32, word & 0x7f) << 2;
        return std.fmt.bufPrint(buf, "sub sp, sp, #{}", .{offset}) catch error.NoSpaceLeft;
    }
    if ((word & 0xfe00) == 0xb400) {
        return formatThumbPush(buf, word);
    }
    if ((word & 0xfe00) == 0xbc00) {
        return formatThumbPop(buf, word);
    }
    if ((word & 0xfff7) == 0xb650) {
        const name = if ((word & 8) != 0) "be" else "le";
        return std.fmt.bufPrint(buf, "setend {}", .{name}) catch error.NoSpaceLeft;
    }
    if ((word & 0xffc0) == 0xb200) {
        return formatThumbUnaryReg(buf, "sxth", word);
    }
    if ((word & 0xffc0) == 0xb240) {
        return formatThumbUnaryReg(buf, "sxtb", word);
    }
    if ((word & 0xffc0) == 0xb280) {
        return formatThumbUnaryReg(buf, "uxth", word);
    }
    if ((word & 0xffc0) == 0xb2c0) {
        return formatThumbUnaryReg(buf, "uxtb", word);
    }
    if ((word & 0xffc0) == 0xba00) {
        return formatThumbUnaryReg(buf, "rev", word);
    }
    if ((word & 0xffc0) == 0xba40) {
        return formatThumbUnaryReg(buf, "rev16", word);
    }
    if ((word & 0xffc0) == 0xbac0) {
        return formatThumbUnaryReg(buf, "revsh", word);
    }
    if ((word & 0xf800) == 0xc000) {
        const base = arm_state.lowReg(word >> 8);
        return formatThumbMultiple(buf, "stm", base, @intCast(u8, word & 0xff), true);
    }
    if ((word & 0xf800) == 0xc800) {
        const base = arm_state.lowReg(word >> 8);
        const mask = @intCast(u8, word & 0xff);
        const write_back = (mask & (@as(u8, 1) << @intCast(u3, @enumToInt(base)))) == 0;
        return formatThumbMultiple(buf, "ldm", base, mask, write_back);
    }
    if ((word & 0xff00) == 0xde00) {
        return std.fmt.bufPrint(buf, "udf", .{}) catch error.NoSpaceLeft;
    }
    if ((word & 0xff00) == 0xdf00) {
        return std.fmt.bufPrint(buf, "svc #{}", .{word & 0xff}) catch error.NoSpaceLeft;
    }
    if ((word & 0xf000) == 0xd000 and (word & 0x0f00) < 0x0e00) {
        const code = arm_state.conditionFromNibble(@intCast(u4, (word >> 8) & 0xf)).?;
        const offset = bits.signExtend32(@as(u32, word & 0xff) << 1, 9) + 4;
        return std.fmt.bufPrint(buf, "b{} {c}#{}", .{
            arm_state.conditionSuffix(code),
            signChar(offset),
            abs32(offset),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0xe000) {
        const offset = bits.signExtend32(@as(u32, word & 0x7ff) << 1, 12) + 4;
        return std.fmt.bufPrint(buf, "b {c}#{}", .{
            signChar(offset),
            abs32(offset),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "unknown #{x}", .{word}) catch error.NoSpaceLeft;
}

