const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");
usingnamespace @import("thumb_memory_flow.zig");

pub fn traceThumbMiscFlow(word: u16, pc: u32, tape: *trace.Tape) RunError!bool {
    if ((word & 0xffc0) == 0xb200) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        const half = try tape.lowHalf(source);
        _ = try tape.storeReg(dest, try tape.signExtendHalf(half));
        return true;
    }

    if ((word & 0xffc0) == 0xb240) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        const byte = try tape.lowByte(source);
        _ = try tape.storeReg(dest, try tape.signExtendByte(byte));
        return true;
    }

    if ((word & 0xffc0) == 0xb280) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        const half = try tape.lowHalf(source);
        _ = try tape.storeReg(dest, try tape.zeroExtendHalf(half));
        return true;
    }

    if ((word & 0xffc0) == 0xb2c0) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        const byte = try tape.lowByte(source);
        _ = try tape.storeReg(dest, try tape.zeroExtendByte(byte));
        return true;
    }

    if ((word & 0xffc0) == 0xba00) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        _ = try tape.storeReg(dest, try tape.byteReverseWord(source));
        return true;
    }

    if ((word & 0xffc0) == 0xba40) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        const low = try tape.byteReverseHalf(try tape.lowHalf(source));
        const shift = try tape.literalByte(16);
        const carry_in = try tape.literalBit(false);
        const high_shifted = try tape.shiftRight(source, shift, carry_in);
        const high = try tape.byteReverseHalf(try tape.lowHalf(high_shifted));
        const high_word = try tape.zeroExtendHalf(high);
        const low_word = try tape.zeroExtendHalf(low);
        const moved_high = try tape.shiftLeft(high_word, shift, carry_in);
        _ = try tape.storeReg(dest, try tape.bitwiseOr(moved_high, low_word));
        return true;
    }

    if ((word & 0xffc0) == 0xbac0) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        const half = try tape.byteReverseHalf(try tape.lowHalf(source));
        _ = try tape.storeReg(dest, try tape.signExtendHalf(half));
        return true;
    }

    if ((word & 0xf000) == 0xd000 and (word & 0x0f00) < 0x0e00) {
        const cond = try tape.literalByte(@intCast(u8, (word >> 8) & 0xf));
        const offset = bits.signExtend32(@as(u32, word & 0xff) << 1, 9);
        const taken = try tape.literalWord(@intCast(u32, @intCast(i32, pc + 4) + offset));
        const skipped = try tape.literalWord(pc + 2);
        _ = try tape.branchIf(cond, taken, skipped);
        return true;
    }

    if (isCompareZeroBranch(word)) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word));
        const source = try tape.loadReg(source_reg);
        const zero = try tape.equalZero(source);
        const taken = try tape.literalWord(compareZeroBranchTarget(word, pc));
        const skipped = try tape.literalWord(pc + 2);
        _ = try tape.branchIf(zero, if ((word & 0x0800) == 0) taken else skipped, if ((word & 0x0800) == 0) skipped else taken);
        return true;
    }

    if ((word & 0xf800) == 0xe000) {
        const target = try tape.literalWord(branchTarget(word, pc).?);
        _ = try tape.jump(target);
        return true;
    }

    return false;
}
