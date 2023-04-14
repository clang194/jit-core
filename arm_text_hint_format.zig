const std = @import("std");
const text_data = @import("arm_text_data_format.zig");
const shiftName = text_data.shiftName;
const text_types = @import("arm_text_types.zig");
const TextError = text_types.TextError;
const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
usingnamespace @import("arm_text_types.zig");
usingnamespace @import("arm_text_data_format.zig");

pub fn formatArmPreload(buf: []u8, word: u32) TextError![]u8 {
    const op = if (bits.getBit32(word, 22)) "pld" else "pldw";
    const base = @intToEnum(arm_state.ArmReg, @intCast(u8, (word >> 16) & 0xf));
    if (!bits.getBit32(word, 25)) {
        const sign: []const u8 = if (bits.getBit32(word, 23)) "+" else "-";
        return std.fmt.bufPrint(buf, "{} [{}, #{}{}]", .{
            op,
            arm_state.regName(base),
            sign,
            word & 0xfff,
        }) catch error.NoSpaceLeft;
    }

    var offset_buf: [48]u8 = undefined;
    const offset = try formatPreloadRegister(offset_buf[0..], word);
    return std.fmt.bufPrint(buf, "{} [{}, {}]", .{
        op,
        arm_state.regName(base),
        offset,
    }) catch error.NoSpaceLeft;
}

fn formatPreloadRegister(buf: []u8, word: u32) TextError![]u8 {
    const source = @intToEnum(arm_state.ArmReg, @intCast(u8, word & 0xf));
    const mode = @intCast(u2, (word >> 5) & 0x3);
    const amount = @intCast(u8, (word >> 7) & 0x1f);
    const prefix: []const u8 = if (bits.getBit32(word, 23)) "+" else "-";
    if (mode == 0 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}{}", .{ prefix, arm_state.regName(source) }) catch error.NoSpaceLeft;
    }
    if (mode == 1 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}{}, lsr #32", .{ prefix, arm_state.regName(source) }) catch error.NoSpaceLeft;
    }
    if (mode == 2 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}{}, asr #32", .{ prefix, arm_state.regName(source) }) catch error.NoSpaceLeft;
    }
    if (mode == 3 and amount == 0) {
        return std.fmt.bufPrint(buf, "{}{}, rrx", .{ prefix, arm_state.regName(source) }) catch error.NoSpaceLeft;
    }
    return std.fmt.bufPrint(buf, "{}{}, {} #{}", .{
        prefix,
        arm_state.regName(source),
        shiftName(mode),
        amount,
    }) catch error.NoSpaceLeft;
}
