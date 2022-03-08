const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");
usingnamespace @import("thumb_memory_flow.zig");

pub fn runThumbAluFlow(word: u16, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!bool {
    if ((word & 0xf800) == 0x0000) {
        const amount = @intCast(u8, (word >> 6) & 0x1f);
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = logicalLeft(state.read(source), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return true;
    }

    if ((word & 0xf800) == 0x0800) {
        var amount = @intCast(u8, (word >> 6) & 0x1f);
        if (amount == 0) {
            amount = 32;
        }
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = logicalRight(state.read(source), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return true;
    }

    if ((word & 0xf800) == 0x1000) {
        var amount = @intCast(u8, (word >> 6) & 0x1f);
        if (amount == 0) {
            amount = 32;
        }
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = arithmeticRight(state.read(source), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return true;
    }

    if ((word & 0xfe00) == 0x1800) {
        const addend = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = addWithCarry(state.read(base), state.read(addend), false);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return true;
    }

    if ((word & 0xfe00) == 0x1a00) {
        const subtrahend = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = subWithCarry(state.read(base), state.read(subtrahend), true);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return true;
    }

    if ((word & 0xfe00) == 0x1c00) {
        const amount = @intCast(u32, (word >> 6) & 7);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = addWithCarry(state.read(base), amount, false);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return true;
    }

    if ((word & 0xfe00) == 0x1e00) {
        const amount = @intCast(u32, (word >> 6) & 7);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = subWithCarry(state.read(base), amount, true);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return true;
    }

    if ((word & 0xf800) == 0x2000) {
        const dest = arm_state.lowReg(word >> 8);
        const result = @intCast(u32, word & 0xff);
        state.write(dest, result);
        updateNz(state, result);
        return true;
    }

    if ((word & 0xf800) == 0x2800) {
        const source = arm_state.lowReg(word >> 8);
        const amount = @intCast(u32, word & 0xff);
        const result = subWithCarry(state.read(source), amount, true);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return true;
    }

    if ((word & 0xf800) == 0x3000) {
        const dest = arm_state.lowReg(word >> 8);
        const amount = @intCast(u32, word & 0xff);
        const result = addWithCarry(state.read(dest), amount, false);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return true;
    }

    if ((word & 0xf800) == 0x3800) {
        const dest = arm_state.lowReg(word >> 8);
        const amount = @intCast(u32, word & 0xff);
        const result = subWithCarry(state.read(dest), amount, true);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return true;
    }

    if ((word & 0xffc0) == 0x4000) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) & state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return true;
    }

    if ((word & 0xffc0) == 0x4040) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) ^ state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return true;
    }

    if ((word & 0xffc0) == 0x4080) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const amount = bits.lowByte(state.read(source));
        const result = logicalLeft(state.read(dest), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return true;
    }

    if ((word & 0xffc0) == 0x40c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const amount = bits.lowByte(state.read(source));
        const result = logicalRight(state.read(dest), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return true;
    }

    if ((word & 0xffc0) == 0x4100) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const amount = bits.lowByte(state.read(source));
        const result = arithmeticRight(state.read(dest), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return true;
    }

    if ((word & 0xffc0) == 0x4140) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = addWithCarry(state.read(dest), state.read(source), state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return true;
    }

    if ((word & 0xffc0) == 0x4180) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = subWithCarry(state.read(dest), state.read(source), state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return true;
    }

    if ((word & 0xffc0) == 0x41c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const amount = bits.lowByte(state.read(source));
        const result = rotateRight(state.read(dest), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return true;
    }

    if ((word & 0xffc0) == 0x4200) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        updateNz(state, state.read(dest) & state.read(source));
        return true;
    }

    if ((word & 0xffc0) == 0x4240) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = subWithCarry(0, state.read(source), true);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return true;
    }

    if ((word & 0xffc0) == 0x4280) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = subWithCarry(state.read(dest), state.read(source), true);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return true;
    }

    if ((word & 0xffc0) == 0x42c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = addWithCarry(state.read(dest), state.read(source), false);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return true;
    }

    if ((word & 0xffc0) == 0x4300) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) | state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return true;
    }

    if ((word & 0xffc0) == 0x4340) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) *% state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return true;
    }

    if ((word & 0xffc0) == 0x4380) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) & ~state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return true;
    }

    if ((word & 0xffc0) == 0x43c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = ~state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return true;
    }

    if ((word & 0xff00) == 0x4400) {
        const dest = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const addend = arm_state.reg4(word >> 3);
        if (dest == .pc and addend == .pc) {
            return error.Unpredictable;
        }
        const pc = state.read(.pc);
        const left = readOperand(state, dest, pc);
        const right = readOperand(state, addend, pc);
        const result = addWithCarry(left, right, false);
        state.write(dest, result.word);
        return true;
    }

    if ((word & 0xff00) == 0x4500) {
        const left_reg = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const right_reg = arm_state.reg4(word >> 3);
        if ((@enumToInt(left_reg) < 8 and @enumToInt(right_reg) < 8) or left_reg == .pc or right_reg == .pc) {
            return error.Unpredictable;
        }
        const result = subWithCarry(state.read(left_reg), state.read(right_reg), true);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return true;
    }

    if ((word & 0xff00) == 0x4600) {
        const dest = arm_state.reg4(((word >> 4) & 8) | (word & 7));
        const source = arm_state.reg4(word >> 3);
        const pc = state.read(.pc);
        const value = readOperand(state, source, pc);
        if (dest == .pc) {
            state.write(.pc, thumbPcWrite(value));
        } else {
            state.write(dest, value);
        }
        return true;
    }

    if ((word & 0xff87) == 0x4700) {
        const source = arm_state.reg4(word >> 3);
        const pc = state.read(.pc);
        loadWritePc(state, readOperand(state, source, pc));
        return true;
    }

    if ((word & 0xff87) == 0x4780) {
        const source = arm_state.reg4(word >> 3);
        const pc = state.read(.pc);
        const target = readOperand(state, source, pc);
        state.write(.lr, (pc + 2) | 1);
        loadWritePc(state, target);
        return true;
    }
    return false;
}
