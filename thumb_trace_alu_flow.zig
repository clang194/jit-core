const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
const thumb_decode = @import("thumb_fetch_decode.zig");
const RunError = thumb_decode.RunError;
const isStop = thumb_decode.isStop;
const isThumbBreakpoint = thumb_decode.isThumbBreakpoint;
const isThumbNoOp = thumb_decode.isThumbNoOp;
const thumbSystemHint = thumb_decode.thumbSystemHint;
const thumb_memory = @import("thumb_memory_flow.zig");
const traceOperand = thumb_memory.traceOperand;
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");
usingnamespace @import("thumb_memory_flow.zig");

pub fn traceThumbAluFlow(word: u16, pc: u32, tape: *trace.Tape) RunError!bool {
    if (isStop(word)) {
        return true;
    }

    if (isThumbNoOp(word) or isThumbBreakpoint(word)) {
        return true;
    }

    if (thumbSystemHint(word) != null) {
        return true;
    }

    if ((word & 0xff00) == 0xdf00) {
        _ = try tape.callSupervisor(@intCast(u32, word & 0xff));
        return true;
    }

    if ((word & 0xf800) == 0x0000) {
        const amount = @intCast(u8, (word >> 6) & 0x1f);
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const read = try tape.loadReg(source);
        const amount_value = try tape.literalByte(amount);
        const result = try tape.shiftLeft(read, amount_value, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return true;
    }

    if ((word & 0xf800) == 0x0800) {
        var amount = @intCast(u8, (word >> 6) & 0x1f);
        if (amount == 0) {
            amount = 32;
        }
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const read = try tape.loadReg(source);
        const amount_value = try tape.literalByte(amount);
        const result = try tape.shiftRight(read, amount_value, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return true;
    }

    if ((word & 0xf800) == 0x1000) {
        var amount = @intCast(u8, (word >> 6) & 0x1f);
        if (amount == 0) {
            amount = 32;
        }
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const read = try tape.loadReg(source);
        const amount_value = try tape.literalByte(amount);
        const result = try tape.shiftArithmeticRight(read, amount_value, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return true;
    }

    if ((word & 0xfe00) == 0x1800) {
        const addend_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.literalBit(false);
        const base = try tape.loadReg(base_reg);
        const addend = try tape.loadReg(addend_reg);
        const result = try tape.addCarrying(base, addend, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return true;
    }

    if ((word & 0xfe00) == 0x1a00) {
        const subtrahend_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.literalBit(true);
        const base = try tape.loadReg(base_reg);
        const subtrahend = try tape.loadReg(subtrahend_reg);
        const result = try tape.subCarrying(base, subtrahend, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return true;
    }

    if ((word & 0xfe00) == 0x1c00) {
        const amount = try tape.literalWord(@intCast(u32, (word >> 6) & 7));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.literalBit(false);
        const base = try tape.loadReg(base_reg);
        const result = try tape.addCarrying(base, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return true;
    }

    if ((word & 0xfe00) == 0x1e00) {
        const amount = try tape.literalWord(@intCast(u32, (word >> 6) & 7));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.literalBit(true);
        const base = try tape.loadReg(base_reg);
        const result = try tape.subCarrying(base, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return true;
    }

    if ((word & 0xf800) == 0x2000) {
        const result = try tape.literalWord(@intCast(u32, word & 0xff));
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return true;
    }

    if ((word & 0xf800) == 0x2800) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 8));
        const amount = try tape.literalWord(@intCast(u32, word & 0xff));
        const carry_in = try tape.literalBit(true);
        const source = try tape.loadReg(source_reg);
        const result = try tape.subCarrying(source, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return true;
    }

    if ((word & 0xf800) == 0x3000) {
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        const amount = try tape.literalWord(@intCast(u32, word & 0xff));
        const carry_in = try tape.literalBit(false);
        const source = try tape.loadReg(dest);
        const result = try tape.addCarrying(source, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return true;
    }

    if ((word & 0xf800) == 0x3800) {
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        const amount = try tape.literalWord(@intCast(u32, word & 0xff));
        const carry_in = try tape.literalBit(true);
        const source = try tape.loadReg(dest);
        const result = try tape.subCarrying(source, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return true;
    }

    if ((word & 0xffc0) == 0x4000) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const read = try tape.loadReg(dest);
        const mask = try tape.loadReg(source);
        const result = try tape.bitwiseAnd(read, mask);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return true;
    }

    if ((word & 0xffc0) == 0x4040) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const read = try tape.loadReg(dest);
        const mask = try tape.loadReg(source);
        const result = try tape.bitwiseXor(read, mask);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return true;
    }

    if ((word & 0xffc0) == 0x4080) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const amount_word = try tape.loadReg(source);
        const amount = try tape.lowByte(amount_word);
        const read = try tape.loadReg(dest);
        const result = try tape.shiftLeft(read, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return true;
    }

    if ((word & 0xffc0) == 0x40c0) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const amount_word = try tape.loadReg(source);
        const amount = try tape.lowByte(amount_word);
        const read = try tape.loadReg(dest);
        const result = try tape.shiftRight(read, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return true;
    }

    if ((word & 0xffc0) == 0x4100) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const amount_word = try tape.loadReg(source);
        const amount = try tape.lowByte(amount_word);
        const read = try tape.loadReg(dest);
        const result = try tape.shiftArithmeticRight(read, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return true;
    }

    if ((word & 0xffc0) == 0x4140) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const read = try tape.loadReg(dest);
        const addend = try tape.loadReg(source);
        const result = try tape.addCarrying(read, addend, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return true;
    }

    if ((word & 0xffc0) == 0x4180) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const read = try tape.loadReg(dest);
        const subtrahend = try tape.loadReg(source);
        const result = try tape.subCarrying(read, subtrahend, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return true;
    }

    if ((word & 0xffc0) == 0x41c0) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.loadCarry();
        const amount_word = try tape.loadReg(source);
        const amount = try tape.lowByte(amount_word);
        const read = try tape.loadReg(dest);
        const result = try tape.rotateRight(read, amount, carry_in);
        const carry_out = try tape.carryResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        return true;
    }

    if ((word & 0xffc0) == 0x4200) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const read = try tape.loadReg(dest);
        const mask = try tape.loadReg(source);
        const result = try tape.bitwiseAnd(read, mask);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return true;
    }

    if ((word & 0xffc0) == 0x4240) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const zero = try tape.literalWord(0);
        const carry_in = try tape.literalBit(true);
        const source = try tape.loadReg(source_reg);
        const result = try tape.subCarrying(zero, source, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return true;
    }

    if ((word & 0xffc0) == 0x4280) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.literalBit(true);
        const left = try tape.loadReg(dest);
        const right = try tape.loadReg(source_reg);
        const result = try tape.subCarrying(left, right, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return true;
    }

    if ((word & 0xffc0) == 0x42c0) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const carry_in = try tape.literalBit(false);
        const left = try tape.loadReg(dest);
        const right = try tape.loadReg(source_reg);
        const result = try tape.addCarrying(left, right, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return true;
    }

    if ((word & 0xffc0) == 0x4300) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const read = try tape.loadReg(dest);
        const mask = try tape.loadReg(source);
        const result = try tape.bitwiseOr(read, mask);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return true;
    }

    if ((word & 0xffc0) == 0x4380) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const read = try tape.loadReg(dest);
        const mask_read = try tape.loadReg(source);
        const mask = try tape.bitwiseNot(mask_read);
        const result = try tape.bitwiseAnd(read, mask);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return true;
    }

    if ((word & 0xffc0) == 0x43c0) {
        const source = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const read = try tape.loadReg(source);
        const result = try tape.bitwiseNot(read);
        _ = try tape.storeReg(dest, result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        return true;
    }

    if ((word & 0xff00) == 0x4400) {
        const dest_reg = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const addend_reg = arm_state.reg4(word >> 3);
        if (dest_reg == .pc and addend_reg == .pc) {
            return error.Unpredictable;
        }
        const dest = try tape.literalReg(dest_reg);
        const left = try traceOperand(tape, dest_reg, pc);
        const right = try traceOperand(tape, addend_reg, pc);
        const carry_in = try tape.literalBit(false);
        const result = try tape.addCarrying(left, right, carry_in);
        _ = try tape.storeReg(dest, result);
        return true;
    }

    if ((word & 0xff00) == 0x4500) {
        const left_reg = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const right_reg = arm_state.reg4(word >> 3);
        if ((@enumToInt(left_reg) < 8 and @enumToInt(right_reg) < 8) or left_reg == .pc or right_reg == .pc) {
            return error.Unpredictable;
        }
        const left = try traceOperand(tape, left_reg, pc);
        const right = try traceOperand(tape, right_reg, pc);
        const carry_in = try tape.literalBit(true);
        const result = try tape.subCarrying(left, right, carry_in);
        const carry_out = try tape.carryResult(result);
        const overflow = try tape.overflowResult(result);
        _ = try tape.storeNegative(try tape.highBit(result));
        _ = try tape.storeZero(try tape.equalZero(result));
        _ = try tape.storeCarry(carry_out);
        _ = try tape.storeOverflow(overflow);
        return true;
    }

    if ((word & 0xff00) == 0x4600) {
        const dest_reg = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const source_reg = arm_state.reg4(word >> 3);
        const dest = try tape.literalReg(dest_reg);
        const source = try traceOperand(tape, source_reg, pc);
        if (dest_reg == .pc) {
            const mask = try tape.literalWord(0xfffffffe);
            _ = try tape.storeReg(dest, try tape.bitwiseAnd(source, mask));
        } else {
            _ = try tape.storeReg(dest, source);
        }
        return true;
    }

    if ((word & 0xff87) == 0x4700) {
        const source = try traceOperand(tape, arm_state.reg4(word >> 3), pc);
        _ = try tape.loadPc(source);
        return true;
    }

    if ((word & 0xff87) == 0x4780) {
        const link = try tape.literalReg(.lr);
        const source = try traceOperand(tape, arm_state.reg4(word >> 3), pc);
        _ = try tape.storeReg(link, try tape.literalWord((pc + 2) | 1));
        _ = try tape.loadPc(source);
        return true;
    }
    return false;
}
