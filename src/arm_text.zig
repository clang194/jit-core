const std = @import("std");
const bits = @import("bits.zig");
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

    if (((word >> 26) & 0x3) == 0 and bits.getBit32(word, 25)) {
        const code = @intCast(u4, (word >> 21) & 0xf);
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

    return error.UnknownInstruction;
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
    if ((word & 0xff00) == 0x4400) {
        const dest = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const addend = arm_state.reg4(word >> 3);
        return std.fmt.bufPrint(buf, "add {}, {}", .{
            arm_state.regName(dest),
            arm_state.regName(addend),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0xff00) == 0xde00) {
        return std.fmt.bufPrint(buf, "udf", .{}) catch error.NoSpaceLeft;
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

fn condName(cond: u4) []const u8 {
    return switch (cond) {
        0x0 => "eq",
        0x1 => "ne",
        0x2 => "cs",
        0x3 => "cc",
        0x4 => "mi",
        0x5 => "pl",
        0x6 => "vs",
        0x7 => "vc",
        0x8 => "hi",
        0x9 => "ls",
        0xa => "ge",
        0xb => "lt",
        0xc => "gt",
        0xd => "le",
        0xe => "",
        else => "",
    };
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

