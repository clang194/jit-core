const std = @import("std");
const bits = @import("bits.zig");
const arm_exec = @import("arm_exec.zig");
const arm_state = @import("arm_state.zig");

pub const TextError = error{
    UnknownInstruction,
    NoSpaceLeft,
};

pub fn formatArm(buf: []u8, word: u32) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    if (cond == 0xf and ((word >> 25) & 0x7) == 0x5) {
        return formatBranchExchangeImmediate(buf, word);
    }

    const branch_reg = word & 0x0ffffff0;
    if (branch_reg == 0x012fff10 or branch_reg == 0x012fff20 or branch_reg == 0x012fff30) {
        const rm = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
        const suffix = condName(cond);
        if (branch_reg == 0x012fff10) {
            return std.fmt.bufPrint(buf, "bx{} {}", .{ suffix, arm_state.regName(rm) }) catch error.NoSpaceLeft;
        }
        if (branch_reg == 0x012fff20) {
            return std.fmt.bufPrint(buf, "bxj{} {}", .{ suffix, arm_state.regName(rm) }) catch error.NoSpaceLeft;
        }
        if (branch_reg == 0x012fff30) {
            return std.fmt.bufPrint(buf, "blx{} {}", .{ suffix, arm_state.regName(rm) }) catch error.NoSpaceLeft;
        }
    }

    if (((word >> 25) & 0x7) == 0x5) {
        return formatBranchImmediate(buf, word, cond);
    }

    if ((word & 0x0f000000) == 0x0f000000) {
        const code = arm_state.conditionFromNibble(cond) orelse return error.UnknownInstruction;
        return std.fmt.bufPrint(buf, "svc{} #{}", .{
            arm_state.conditionSuffix(code),
            word & 0x00ffffff,
        }) catch error.NoSpaceLeft;
    }

    if ((word & 0xfff000f0) == 0xe7f000f0) {
        return std.fmt.bufPrint(buf, "udf", .{}) catch error.NoSpaceLeft;
    }

    if ((word & 0x0fff0ff0) == 0x06bf0f30) {
        return formatArmUnaryReg(buf, "rev", word, cond);
    }

    if ((word & 0x0fff0ff0) == 0x06ff0fb0) {
        return formatArmUnaryReg(buf, "revsh", word, cond);
    }

    if (((word >> 26) & 0x3) == 0 and bits.getBit32(word, 25)) {
        const code = @intCast(u4, (word >> 21) & 0xf);
        if (code == 0xa and bits.getBit32(word, 20) and ((word >> 12) & 0xf) == 0) {
            const rn = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
            const rotate = @intCast(u8, (word >> 8) & 0xf);
            const imm = @intCast(u8, word & 0xff);
            return std.fmt.bufPrint(buf, "cmp{} {}, #{}", .{
                condName(cond),
                arm_state.regName(rn),
                arm_exec.expandArmImmediate(rotate, imm),
            }) catch error.NoSpaceLeft;
        }
        if (code == 0x5) {
            const rd = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
            const rn = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
            const rotate = @intCast(u8, (word >> 8) & 0xf);
            const imm = @intCast(u8, word & 0xff);
            const flags = if (bits.getBit32(word, 20)) "s" else "";
            return std.fmt.bufPrint(buf, "adc{}{} {}, {}, #{}", .{
                condName(cond),
                flags,
                arm_state.regName(rd),
                arm_state.regName(rn),
                arm_exec.expandArmImmediate(rotate, imm),
            }) catch error.NoSpaceLeft;
        }
        if (code == 0x4) {
            const rd = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
            const rn = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
            const imm = word & 0xff;
            return std.fmt.bufPrint(buf, "add{} {}, {}, #{}", .{
                condName(cond),
                arm_state.regName(rd),
                arm_state.regName(rn),
                imm,
            }) catch error.NoSpaceLeft;
        }
    }

    return std.fmt.bufPrint(buf, "unknown #{x}", .{word}) catch error.NoSpaceLeft;
}

fn formatArmUnaryReg(buf: []u8, comptime op: []const u8, word: u32, cond: u4) TextError![]u8 {
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    return std.fmt.bufPrint(buf, "{}{} {}, {}", .{
        op,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

pub fn formatThumb16(buf: []u8, word: u16) TextError![]u8 {
    if ((word & 0xf800) == 0x0000) {
        return formatThumbShiftImm(buf, "lsls", word);
    }
    if ((word & 0xf800) == 0x0800) {
        return formatThumbShiftImm(buf, "lsrs", word);
    }
    if ((word & 0xf800) == 0x1000) {
        return formatThumbShiftImm(buf, "asrs", word);
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
        return std.fmt.bufPrint(buf, "b{} {}#{}", .{
            arm_state.conditionSuffix(code),
            signText(offset),
            abs32(offset),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xf800) == 0xe000) {
        const offset = bits.signExtend32(@as(u32, word & 0x7ff) << 1, 12) + 4;
        return std.fmt.bufPrint(buf, "b {}#{}", .{
            signText(offset),
            abs32(offset),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "unknown #{x}", .{word}) catch error.NoSpaceLeft;
}

pub fn formatThumb32(buf: []u8, word: u32) TextError![]u8 {
    const first = @intCast(u16, word & 0xffff);
    const second = @intCast(u16, (word >> 16) & 0xffff);
    if ((first & 0xf800) == 0xf000 and (second & 0xf800) == 0xf800) {
        const offset = thumb32Offset(word) + 4;
        return std.fmt.bufPrint(buf, "bl {}#{}", .{
            signText(@intCast(i32, offset)),
            offset,
        }) catch error.NoSpaceLeft;
    }
    if ((first & 0xf800) == 0xf000 and (second & 0xf800) == 0xe800 and (second & 1) == 0) {
        const offset = thumb32Offset(word) + 4;
        return std.fmt.bufPrint(buf, "blx {}#{}", .{
            signText(@intCast(i32, offset)),
            offset,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "unknown #{x}", .{word}) catch error.NoSpaceLeft;
}

fn formatThumbShiftImm(buf: []u8, comptime op: []const u8, word: u16) TextError![]u8 {
    const amount = @intCast(u8, (word >> 6) & 0x1f);
    const source = arm_state.lowReg(word >> 3);
    const dest = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, {}, #{}", .{
        op,
        arm_state.regName(dest),
        arm_state.regName(source),
        amount,
    }) catch error.NoSpaceLeft;
}

fn formatThumbBitReg(buf: []u8, comptime op: []const u8, word: u16) TextError![]u8 {
    const source = arm_state.lowReg(word >> 3);
    const dest = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, {}", .{
        op,
        arm_state.regName(dest),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

fn formatThumbShiftReg(buf: []u8, comptime op: []const u8, word: u16) TextError![]u8 {
    const source = arm_state.lowReg(word >> 3);
    const dest = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, {}", .{
        op,
        arm_state.regName(dest),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

fn formatThumbTransferReg(buf: []u8, comptime op: []const u8, word: u16) TextError![]u8 {
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

fn formatThumbTransferImm(buf: []u8, comptime op: []const u8, word: u16, comptime scale: u5) TextError![]u8 {
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

fn formatThumbUnaryReg(buf: []u8, comptime op: []const u8, word: u16) TextError![]u8 {
    const source = arm_state.lowReg(word >> 3);
    const dest = arm_state.lowReg(word);
    return std.fmt.bufPrint(buf, "{} {}, {}", .{
        op,
        arm_state.regName(dest),
        arm_state.regName(source),
    }) catch error.NoSpaceLeft;
}

fn formatThumbPush(buf: []u8, word: u16) TextError![]u8 {
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

fn formatThumbPop(buf: []u8, word: u16) TextError![]u8 {
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

fn formatThumbMultiple(buf: []u8, comptime op: []const u8, base: arm_state.ArmReg, mask: u8, write_back: bool) TextError![]u8 {
    var used: usize = 0;
    try appendText(buf, &used, op);
    try appendText(buf, &used, " ");
    try appendText(buf, &used, arm_state.regName(base));
    if (write_back) {
        try appendText(buf, &used, "!");
    }
    try appendText(buf, &used, ", {");
    var first = true;
    var index: u8 = 0;
    while (index < 8) : (index += 1) {
        if ((mask & (@as(u8, 1) << @intCast(u3, index))) != 0) {
            if (!first) {
                try appendText(buf, &used, ", ");
            }
            try appendText(buf, &used, arm_state.regName(@intToEnum(arm_state.ArmReg, index)));
            first = false;
        }
    }
    try appendText(buf, &used, "}");
    return buf[0..used];
}

fn appendText(buf: []u8, used: *usize, text: []const u8) TextError!void {
    if (used.* + text.len > buf.len) {
        return error.NoSpaceLeft;
    }
    std.mem.copy(u8, buf[used.* .. used.* + text.len], text);
    used.* += text.len;
}

fn formatBranchImmediate(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const link = bits.getBit32(word, 24);
    const imm = word & 0x00ffffff;
    const offset = bits.signExtend32(imm << 2, 26) + 8;
    const op: []const u8 = if (link) "bl" else "b";
    return std.fmt.bufPrint(buf, "{}{} {}#{}", .{
        op,
        condName(cond),
        signText(offset),
        abs32(offset),
    }) catch error.NoSpaceLeft;
}

fn formatBranchExchangeImmediate(buf: []u8, word: u32) TextError![]u8 {
    const high = @as(u32, @boolToInt(bits.getBit32(word, 24)));
    const imm = word & 0x00ffffff;
    const offset = bits.signExtend32((imm << 2) | (high << 1), 26) + 8;
    return std.fmt.bufPrint(buf, "blx {}#{}", .{ signText(offset), abs32(offset) }) catch error.NoSpaceLeft;
}

fn thumb32Offset(word: u32) u32 {
    const first = word & 0x07ff;
    const second = (word >> 16) & 0x07ff;
    return (first << 12) | (second << 1);
}

fn condName(cond: u4) []const u8 {
    if (arm_state.conditionFromNibble(cond)) |code| {
        return arm_state.conditionSuffix(code);
    }
    return "";
}

fn signText(value: i32) []const u8 {
    if (value < 0) {
        return "-";
    }
    return "+";
}

fn abs32(value: i32) u32 {
    if (value < 0) {
        return @intCast(u32, -value);
    }
    return @intCast(u32, value);
}
