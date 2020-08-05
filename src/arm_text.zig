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

    if ((word & 0x0ff000f0) == 0x01200070) {
        const value = (((word >> 8) & 0xfff) << 4) | (word & 0xf);
        return std.fmt.bufPrint(buf, "bkpt #{}", .{value}) catch error.NoSpaceLeft;
    }

    if ((word & 0x0fffffff) == 0x0320f000) {
        return std.fmt.bufPrint(buf, "nop", .{}) catch error.NoSpaceLeft;
    }

    if ((word & 0x0fff0ff0) == 0x06bf0f30) {
        return formatArmUnaryReg(buf, "rev", word, cond);
    }

    if (arm_exec.isRevHalfwords(word)) {
        return formatArmUnaryReg(buf, "rev16", word, cond);
    }

    if ((word & 0x0fff0ff0) == 0x06ff0fb0) {
        return formatArmUnaryReg(buf, "revsh", word, cond);
    }

    if (armExtendText(word)) |info| {
        return formatArmExtend(buf, word, info);
    }

    if (arm_exec.isMultiply(word)) {
        return formatArmMultiply(buf, word);
    }

    if (arm_exec.isDataProcessing(word)) {
        return formatArmData(buf, word);
    }

    return std.fmt.bufPrint(buf, "unknown #{x}", .{word}) catch error.NoSpaceLeft;
}

const ArmExtendText = struct {
    name: []const u8,
    base: bool,
};

fn formatArmExtend(buf: []u8, word: u32, info: ArmExtendText) TextError![]u8 {
    const cond = @intCast(u4, word >> 28);
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    var source_buf: [32]u8 = undefined;
    const source = try formatExtendSource(source_buf[0..], word);
    if (info.base) {
        const base = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
        return std.fmt.bufPrint(buf, "{}{} {}, {}, {}", .{
            info.name,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(base),
            source,
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{} {}, {}", .{
        info.name,
        condName(cond),
        arm_state.regName(dest),
        source,
    }) catch error.NoSpaceLeft;
}

fn formatExtendSource(buf: []u8, word: u32) TextError![]u8 {
    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const rotate = @intCast(u8, ((word >> 10) & 0x3) * 8);
    if (rotate == 0) {
        return std.fmt.bufPrint(buf, "{}", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}, ror #{}", .{ arm_state.regName(source), rotate }) catch error.NoSpaceLeft;
}

fn armExtendText(word: u32) ?ArmExtendText {
    if (arm_state.conditionFromNibble(@intCast(u4, word >> 28)) == null) {
        return null;
    }
    if ((word & 0x0fff03f0) == 0x068f0070) {
        return ArmExtendText{ .name = "sxtb16", .base = false };
    }
    if ((word & 0x0fff03f0) == 0x06af0070) {
        return ArmExtendText{ .name = "sxtb", .base = false };
    }
    if ((word & 0x0fff03f0) == 0x06bf0070) {
        return ArmExtendText{ .name = "sxth", .base = false };
    }
    if ((word & 0x0fff03f0) == 0x06cf0070) {
        return ArmExtendText{ .name = "uxtb16", .base = false };
    }
    if ((word & 0x0fff03f0) == 0x06ef0070) {
        return ArmExtendText{ .name = "uxtb", .base = false };
    }
    if ((word & 0x0fff03f0) == 0x06ff0070) {
        return ArmExtendText{ .name = "uxth", .base = false };
    }
    if ((word & 0x0ff003f0) == 0x06800070) {
        return ArmExtendText{ .name = "sxtab16", .base = true };
    }
    if ((word & 0x0ff003f0) == 0x06a00070) {
        return ArmExtendText{ .name = "sxtab", .base = true };
    }
    if ((word & 0x0ff003f0) == 0x06b00070) {
        return ArmExtendText{ .name = "sxtah", .base = true };
    }
    if ((word & 0x0ff003f0) == 0x06c00070) {
        return ArmExtendText{ .name = "uxtab16", .base = true };
    }
    if ((word & 0x0ff003f0) == 0x06e00070) {
        return ArmExtendText{ .name = "uxtab", .base = true };
    }
    if ((word & 0x0ff003f0) == 0x06f00070) {
        return ArmExtendText{ .name = "uxtah", .base = true };
    }
    return null;
}

const MultiplyText = struct {
    name: []const u8,
    long: bool,
    addend: bool,
    flags: bool,
};

fn formatArmMultiply(buf: []u8, word: u32) TextError![]u8 {
    const info = multiplyText(word) orelse return error.UnknownInstruction;
    const cond = @intCast(u4, word >> 28);
    const flags = if (info.flags and bits.getBit32(word, 20)) "s" else "";
    const dest_hi = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const dest_lo = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const right = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 8) & 0xf));
    const left = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));

    if (info.long) {
        return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}, {}", .{
            info.name,
            condName(cond),
            flags,
            arm_state.regName(dest_lo),
            arm_state.regName(dest_hi),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }

    if (info.addend) {
        return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}, {}", .{
            info.name,
            condName(cond),
            flags,
            arm_state.regName(dest_hi),
            arm_state.regName(left),
            arm_state.regName(right),
            arm_state.regName(dest_lo),
        }) catch error.NoSpaceLeft;
    }

    return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}", .{
        info.name,
        condName(cond),
        flags,
        arm_state.regName(dest_hi),
        arm_state.regName(left),
        arm_state.regName(right),
    }) catch error.NoSpaceLeft;
}

fn multiplyText(word: u32) ?MultiplyText {
    if (arm_state.conditionFromNibble(@intCast(u4, word >> 28)) == null) {
        return null;
    }
    if ((word & 0x0fe0f0f0) == 0x00000090) {
        return MultiplyText{ .name = "mul", .long = false, .addend = false, .flags = true };
    }
    if ((word & 0x0fe000f0) == 0x00200090) {
        return MultiplyText{ .name = "mla", .long = false, .addend = true, .flags = true };
    }
    if ((word & 0x0fe000f0) == 0x00800090) {
        return MultiplyText{ .name = "umull", .long = true, .addend = false, .flags = true };
    }
    if ((word & 0x0fe000f0) == 0x00a00090) {
        return MultiplyText{ .name = "umlal", .long = true, .addend = false, .flags = true };
    }
    if ((word & 0x0ff000f0) == 0x00400090) {
        return MultiplyText{ .name = "umaal", .long = true, .addend = false, .flags = false };
    }
    if ((word & 0x0fe000f0) == 0x00c00090) {
        return MultiplyText{ .name = "smull", .long = true, .addend = false, .flags = true };
    }
    if ((word & 0x0fe000f0) == 0x00e00090) {
        return MultiplyText{ .name = "smlal", .long = true, .addend = false, .flags = true };
    }
    return null;
}

fn formatArmData(buf: []u8, word: u32) TextError![]u8 {
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

fn formatArmOperand2(buf: []u8, word: u32) TextError![]u8 {
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

fn dataName(op: u4) ?[]const u8 {
    return switch (op) {
        0x0 => "and",
        0x1 => "eor",
        0x2 => "sub",
        0x3 => null,
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

fn shiftName(mode: u2) []const u8 {
    return switch (mode) {
        0 => "lsl",
        1 => "lsr",
        2 => "asr",
        3 => "ror",
    };
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
            signText(offset),
            abs32(offset),
        }) catch error.NoSpaceLeft;
    }
    if ((first & 0xf800) == 0xf000 and (second & 0xf800) == 0xe800 and (second & 1) == 0) {
        const offset = thumb32Offset(word) + 4;
        return std.fmt.bufPrint(buf, "blx {}#{}", .{
            signText(offset),
            abs32(offset),
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

fn thumb32Offset(word: u32) i32 {
    const first = word & 0x07ff;
    const second = (word >> 16) & 0x07ff;
    return bits.signExtend32((first << 12) | (second << 1), 23);
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
