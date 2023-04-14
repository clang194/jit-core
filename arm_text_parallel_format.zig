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
usingnamespace @import("arm_text_multiply_format.zig");
usingnamespace @import("arm_text_transfer_format.zig");
usingnamespace @import("arm_text_data_format.zig");
usingnamespace @import("arm_text_thumb_format.zig");
usingnamespace @import("arm_text_thumb32_format.zig");
usingnamespace @import("arm_text_common_format.zig");

pub fn isSaturatingArmFormat(word: u32) bool {
    return (word & 0x0fe00030) == 0x06a00010 or
        (word & 0x0ff00ff0) == 0x06a00f30 or
        (word & 0x0fe00030) == 0x06e00010 or
        (word & 0x0ff00ff0) == 0x06e00f30;
}

pub fn formatSaturatingArm(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const unsigned = (word & 0x00400000) != 0;
    const half = (word & 0x00000fc0) == 0x00000f00;
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    if (half) {
        const sat = @intCast(u8, (word >> 16) & 0xf) + if (unsigned) 0 else 1;
        const op = if (unsigned) "usat16" else "ssat16";
        return std.fmt.bufPrint(buf, "{}{} {}, #{}, {}", .{
            op,
            condName(cond),
            arm_state.regName(dest),
            sat,
            arm_state.regName(source),
        }) catch error.NoSpaceLeft;
    }

    const sat = @intCast(u8, (word >> 16) & 0x1f) + if (unsigned) 0 else 1;
    const mode: u2 = if (bits.getBit32(word, 6)) 2 else 0;
    const amount = @intCast(u8, (word >> 7) & 0x1f);
    var shift_buf: [24]u8 = undefined;
    const shift = try formatPackShift(shift_buf[0..], mode, amount);
    const op = if (unsigned) "usat" else "ssat";
    return std.fmt.bufPrint(buf, "{}{} {}, #{}, {}{}", .{
        op,
        condName(cond),
        arm_state.regName(dest),
        sat,
        arm_state.regName(source),
        shift,
    }) catch error.NoSpaceLeft;
}

pub fn saturatingBinaryName(word: u32) ?[]const u8 {
    if (arm_state.conditionFromNibble(@intCast(u4, word >> 28)) == null) {
        return null;
    }
    const op = word & 0x0ff00ff0;
    if (op == 0x01000050) {
        return "qadd";
    }
    if (op == 0x01200050) {
        return "qsub";
    }
    if (op == 0x01400050) {
        return "qdadd";
    }
    if (op == 0x01600050) {
        return "qdsub";
    }
    return null;
}

pub fn formatSaturatingBinary(buf: []u8, op: []const u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "{}{} {}, {}, {}", .{
        op,
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word)),
        arm_state.regName(armReg(word >> 16)),
    }) catch error.NoSpaceLeft;
}

pub fn parallelSaturatingName(word: u32) ?[]const u8 {
    if (arm_state.conditionFromNibble(@intCast(u4, word >> 28)) == null) {
        return null;
    }
    const op = word & 0x0ff00ff0;
    if (op == 0x06200f90) return "qadd8";
    if (op == 0x06200f10) return "qadd16";
    if (op == 0x06200f30) return "qasx";
    if (op == 0x06200f50) return "qsax";
    if (op == 0x06200ff0) return "qsub8";
    if (op == 0x06200f70) return "qsub16";
    if (op == 0x06600f90) return "uqadd8";
    if (op == 0x06600f10) return "uqadd16";
    if (op == 0x06600f30) return "uqasx";
    if (op == 0x06600f50) return "uqsax";
    if (op == 0x06600ff0) return "uqsub8";
    if (op == 0x06600f70) return "uqsub16";
    return null;
}

pub fn parallelHalvingName(word: u32) ?[]const u8 {
    if (arm_state.conditionFromNibble(@intCast(u4, word >> 28)) == null) {
        return null;
    }
    const op = word & 0x0ff00ff0;
    if (op == 0x06300f90) return "shadd8";
    if (op == 0x06300f10) return "shadd16";
    if (op == 0x06300f30) return "shasx";
    if (op == 0x06300f50) return "shsax";
    if (op == 0x06300ff0) return "shsub8";
    if (op == 0x06300f70) return "shsub16";
    if (op == 0x06700f90) return "uhadd8";
    if (op == 0x06700f10) return "uhadd16";
    if (op == 0x06700f30) return "uhasx";
    if (op == 0x06700f50) return "uhsax";
    if (op == 0x06700ff0) return "uhsub8";
    if (op == 0x06700f70) return "uhsub16";
    return null;
}

pub fn parallelWrappingName(word: u32) ?[]const u8 {
    if (arm_state.conditionFromNibble(@intCast(u4, word >> 28)) == null) {
        return null;
    }
    const op = word & 0x0ff00ff0;
    if (op == 0x06100f90) return "sadd8";
    if (op == 0x06100f10) return "sadd16";
    if (op == 0x06100f30) return "sasx";
    if (op == 0x06100f50) return "ssax";
    if (op == 0x06100ff0) return "ssub8";
    if (op == 0x06100f70) return "ssub16";
    if (op == 0x06500f90) return "uadd8";
    if (op == 0x06500f10) return "uadd16";
    if (op == 0x06500f30) return "uasx";
    if (op == 0x06500f50) return "usax";
    if (op == 0x06500ff0) return "usub8";
    if (op == 0x06500f70) return "usub16";
    return null;
}

pub fn formatParallelThreeReg(buf: []u8, op: []const u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "{}{} {}, {}, {}", .{
        op,
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
        arm_state.regName(armReg(word)),
    }) catch error.NoSpaceLeft;
}

pub fn isByteSelectFormat(word: u32) bool {
    return (word & 0x0ff00ff0) == 0x06800fb0 and arm_state.conditionFromNibble(@intCast(u4, word >> 28)) != null;
}

pub fn formatByteSelect(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    return std.fmt.bufPrint(buf, "sel{} {}, {}, {}", .{
        condName(cond),
        arm_state.regName(armReg(word >> 12)),
        arm_state.regName(armReg(word >> 16)),
        arm_state.regName(armReg(word)),
    }) catch error.NoSpaceLeft;
}

pub fn isHalfMultiplyFormat(word: u32) bool {
    return (word & 0x0ff00090) == 0x01400080 or
        (word & 0x0ff00090) == 0x01000080 or
        (word & 0x0ff0f090) == 0x01600080 or
        (word & 0x0ff000b0) == 0x01200080 or
        (word & 0x0ff0f0b0) == 0x012000a0;
}

pub fn formatHalfMultiply(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const addend = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const right = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 8) & 0xf));
    const left = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const y = if (bits.getBit32(word, 6)) "t" else "b";
    const x = if (bits.getBit32(word, 5)) "t" else "b";
    if ((word & 0x0ff00090) == 0x01400080) {
        return std.fmt.bufPrint(buf, "smlal{}{}{} {}, {}, {}, {}", .{
            x,
            y,
            condName(cond),
            arm_state.regName(addend),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff00090) == 0x01000080) {
        return std.fmt.bufPrint(buf, "smla{}{}{} {}, {}, {}, {}", .{
            x,
            y,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
            arm_state.regName(addend),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff0f090) == 0x01600080) {
        return std.fmt.bufPrint(buf, "smul{}{}{} {}, {}, {}", .{
            x,
            y,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff000b0) == 0x01200080) {
        return std.fmt.bufPrint(buf, "smlaw{}{} {}, {}, {}, {}", .{
            y,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
            arm_state.regName(addend),
        }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "smulw{}{} {}, {}, {}", .{
        y,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(left),
        arm_state.regName(right),
    }) catch error.NoSpaceLeft;
}

pub fn isDualMultiplyFormat(word: u32) bool {
    return (word & 0x0ff000d0) == 0x07000010 or
        (word & 0x0ff000d0) == 0x07400010 or
        (word & 0x0ff000d0) == 0x07000050 or
        (word & 0x0ff000d0) == 0x07400050 or
        (word & 0x0ff0f0d0) == 0x0700f010 or
        (word & 0x0ff0f0d0) == 0x0700f050;
}

pub fn formatDualMultiply(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const addend = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const right = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 8) & 0xf));
    const left = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const exchange = if (bits.getBit32(word, 5)) "x" else "";
    if ((word & 0x0ff000d0) == 0x07400010) {
        return std.fmt.bufPrint(buf, "smlald{}{} {}, {}, {}, {}", .{
            exchange,
            condName(cond),
            arm_state.regName(addend),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff000d0) == 0x07400050) {
        return std.fmt.bufPrint(buf, "smlsld{}{} {}, {}, {}, {}", .{
            exchange,
            condName(cond),
            arm_state.regName(addend),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff0f0d0) == 0x0700f010) {
        return std.fmt.bufPrint(buf, "smuad{}{} {}, {}, {}", .{
            exchange,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }
    if ((word & 0x0ff0f0d0) == 0x0700f050) {
        return std.fmt.bufPrint(buf, "smusd{}{} {}, {}, {}", .{
            exchange,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }

    const op = if ((word & 0x0ff000d0) == 0x07000050) "smlsd" else "smlad";
    return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}, {}", .{
        op,
        exchange,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(left),
        arm_state.regName(right),
        arm_state.regName(addend),
    }) catch error.NoSpaceLeft;
}

pub fn isPackHalfword(word: u32) bool {
    return (word & 0x0ff00070) == 0x06800010 or (word & 0x0ff00070) == 0x06800050;
}

pub fn formatPackHalfword(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const top = (word & 0x0ff00070) == 0x06800050;
    const op = if (top) "pkhtb" else "pkhbt";
    const mode: u2 = if (top) 2 else 0;
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const base = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const amount = @intCast(u8, (word >> 7) & 0x1f);
    var shift_buf: [24]u8 = undefined;
    const shift = try formatPackShift(shift_buf[0..], mode, amount);
    return std.fmt.bufPrint(buf, "{}{} {}, {}, {}{}", .{
        op,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(base),
        arm_state.regName(source),
        shift,
    }) catch error.NoSpaceLeft;
}

pub fn formatPackShift(buf: []u8, mode: u2, amount: u8) TextError![]u8 {
    if (mode == 0 and amount == 0) {
        return buf[0..0];
    }
    if (mode == 2 and amount == 0) {
        return std.fmt.bufPrint(buf, ", asr #32", .{}) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, ", {} #{}", .{ shiftName(mode), amount }) catch error.NoSpaceLeft;
}

pub fn isSignedTopMultiply(word: u32) bool {
    return (word & 0x0ff0f0d0) == 0x0750f010 or
        (word & 0x0ff000d0) == 0x07500010 or
        (word & 0x0ff000d0) == 0x075000d0;
}

pub fn formatSignedTopMultiply(buf: []u8, word: u32, cond: u4) TextError![]u8 {
    const rounded = if (bits.getBit32(word, 5)) "r" else "";
    const dest = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    const left = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const right = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 8) & 0xf));
    if ((word & 0x0ff0f0d0) == 0x0750f010) {
        return std.fmt.bufPrint(buf, "smmul{}{} {}, {}, {}", .{
            rounded,
            condName(cond),
            arm_state.regName(dest),
            arm_state.regName(left),
            arm_state.regName(right),
        }) catch error.NoSpaceLeft;
    }

    const addend = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 12) & 0xf));
    const op = if ((word & 0x0ff000d0) == 0x075000d0) "smmls" else "smmla";
    return std.fmt.bufPrint(buf, "{}{}{} {}, {}, {}, {}", .{
        op,
        rounded,
        condName(cond),
        arm_state.regName(dest),
        arm_state.regName(left),
        arm_state.regName(right),
        arm_state.regName(addend),
    }) catch error.NoSpaceLeft;
}

pub fn formatExtendSource(buf: []u8, word: u32) TextError![]u8 {
    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const rotate = @intCast(u8, ((word >> 10) & 0x3) * 8);
    if (rotate == 0) {
        return std.fmt.bufPrint(buf, "{}", .{arm_state.regName(source)}) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}, ror #{}", .{ arm_state.regName(source), rotate }) catch error.NoSpaceLeft;
}

pub fn armExtendText(word: u32) ?ArmExtendText {
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
