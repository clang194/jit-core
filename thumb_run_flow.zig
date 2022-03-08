const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_trace_flow.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");
usingnamespace @import("thumb_memory_flow.zig");

pub fn runThumb(word: u16, state: *arm_state.MachineState) RunError!void {
    return runThumbWithHooks(word, state, arm_state.HostHooks.empty());
}

pub fn runThumbPacketWithHooks(packet: ThumbWord, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!void {
    if (packet.size == 2) {
        return runThumbWithHooks(@intCast(u16, packet.word & 0xffff), state, hooks);
    }
    if (packet.size == 4) {
        return runThumb32WithHooks(packet.word, state, hooks);
    }
    return error.UnknownInstruction;
}

pub fn runThumb32WithHooks(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!void {
    _ = hooks;
    const pc = state.read(.pc);
    if (branchLinkTarget(word, pc)) |target| {
        state.write(.lr, (pc + 4) | 1);
        state.write(.pc, target);
        return;
    }
    if (try branchLinkExchangeTarget(word, pc)) |target| {
        state.write(.lr, (pc + 4) | 1);
        state.setThumb(false);
        state.write(.pc, target);
        return;
    }
    return error.UnknownInstruction;
}

pub fn runThumbWithHooks(word: u16, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!void {
    if (isStop(word)) {
        return;
    }

    if ((word & 0xff00) == 0xdf00) {
        if (hooks.supervisor) |callback| {
            state.write(.pc, state.read(.pc) + 2);
            callback(@intCast(u32, word & 0xff), state);
            return;
        }
        if (hooks.fallback) |callback| {
            callback(state.read(.pc), state, hooks.context);
            return;
        }
        return error.UnknownInstruction;
    }

    if ((word & 0xf800) == 0x0000) {
        const amount = @intCast(u8, (word >> 6) & 0x1f);
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = logicalLeft(state.read(source), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return;
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
        return;
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
        return;
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
        return;
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
        return;
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
        return;
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
        return;
    }

    if ((word & 0xf800) == 0x2000) {
        const dest = arm_state.lowReg(word >> 8);
        const result = @intCast(u32, word & 0xff);
        state.write(dest, result);
        updateNz(state, result);
        return;
    }

    if ((word & 0xf800) == 0x2800) {
        const source = arm_state.lowReg(word >> 8);
        const amount = @intCast(u32, word & 0xff);
        const result = subWithCarry(state.read(source), amount, true);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xf800) == 0x3000) {
        const dest = arm_state.lowReg(word >> 8);
        const amount = @intCast(u32, word & 0xff);
        const result = addWithCarry(state.read(dest), amount, false);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xf800) == 0x3800) {
        const dest = arm_state.lowReg(word >> 8);
        const amount = @intCast(u32, word & 0xff);
        const result = subWithCarry(state.read(dest), amount, true);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xffc0) == 0x4000) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) & state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return;
    }

    if ((word & 0xffc0) == 0x4040) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) ^ state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return;
    }

    if ((word & 0xffc0) == 0x4080) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const amount = bits.lowByte(state.read(source));
        const result = logicalLeft(state.read(dest), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return;
    }

    if ((word & 0xffc0) == 0x40c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const amount = bits.lowByte(state.read(source));
        const result = logicalRight(state.read(dest), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return;
    }

    if ((word & 0xffc0) == 0x4100) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const amount = bits.lowByte(state.read(source));
        const result = arithmeticRight(state.read(dest), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return;
    }

    if ((word & 0xffc0) == 0x4140) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = addWithCarry(state.read(dest), state.read(source), state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xffc0) == 0x4180) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = subWithCarry(state.read(dest), state.read(source), state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xffc0) == 0x41c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const amount = bits.lowByte(state.read(source));
        const result = rotateRight(state.read(dest), amount, state.carry());
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        return;
    }

    if ((word & 0xffc0) == 0x4200) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        updateNz(state, state.read(dest) & state.read(source));
        return;
    }

    if ((word & 0xffc0) == 0x4240) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = subWithCarry(0, state.read(source), true);
        state.write(dest, result.word);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xffc0) == 0x4280) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = subWithCarry(state.read(dest), state.read(source), true);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xffc0) == 0x42c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = addWithCarry(state.read(dest), state.read(source), false);
        updateNz(state, result.word);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
        return;
    }

    if ((word & 0xffc0) == 0x4300) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) | state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return;
    }

    if ((word & 0xffc0) == 0x4340) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) *% state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return;
    }

    if ((word & 0xffc0) == 0x4380) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = state.read(dest) & ~state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return;
    }

    if ((word & 0xffc0) == 0x43c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        const result = ~state.read(source);
        state.write(dest, result);
        updateNz(state, result);
        return;
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
        return;
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
        return;
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
        return;
    }

    if ((word & 0xff87) == 0x4700) {
        const source = arm_state.reg4(word >> 3);
        const pc = state.read(.pc);
        loadWritePc(state, readOperand(state, source, pc));
        return;
    }

    if ((word & 0xff87) == 0x4780) {
        const source = arm_state.reg4(word >> 3);
        const pc = state.read(.pc);
        const target = readOperand(state, source, pc);
        state.write(.lr, (pc + 2) | 1);
        loadWritePc(state, target);
        return;
    }

    if ((word & 0xf800) == 0x4800) {
        const dest = arm_state.lowReg(word >> 8);
        const pc = state.read(.pc);
        const address = alignDown4(pc + 4) + (@as(u32, word & 0xff) << 2);
        state.write(dest, try readMemory32(state, hooks, address));
        return;
    }

    if ((word & 0xfe00) == 0x5000) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const data = arm_state.lowReg(word);
        try writeMemory32(state, hooks, state.read(base) + state.read(source), state.read(data));
        return;
    }

    if ((word & 0xfe00) == 0x5200) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const data = arm_state.lowReg(word);
        try writeMemory16(state, hooks, state.read(base) + state.read(source), @intCast(u16, state.read(data) & 0xffff));
        return;
    }

    if ((word & 0xfe00) == 0x5400) {
        const write8 = hooks.memory.write8 orelse return error.MissingWrite;
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const data = arm_state.lowReg(word);
        write8(state.read(base) + state.read(source), bits.lowByte(state.read(data)));
        return;
    }

    if ((word & 0xfe00) == 0x5600) {
        const read8 = hooks.memory.read8 orelse return error.MissingRead;
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendByte(read8(state.read(base) + state.read(source))));
        return;
    }

    if ((word & 0xfe00) == 0x5800) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, try readMemory32(state, hooks, state.read(base) + state.read(source)));
        return;
    }

    if ((word & 0xfe00) == 0x5a00) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, try readMemory16(state, hooks, state.read(base) + state.read(source)));
        return;
    }

    if ((word & 0xfe00) == 0x5c00) {
        const read8 = hooks.memory.read8 orelse return error.MissingRead;
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, read8(state.read(base) + state.read(source)));
        return;
    }

    if ((word & 0xfe00) == 0x5e00) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendHalf(try readMemory16(state, hooks, state.read(base) + state.read(source))));
        return;
    }

    if ((word & 0xf800) == 0x6000) {
        const data = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f) << 2;
        try writeMemory32(state, hooks, state.read(base) + offset, state.read(data));
        return;
    }

    if ((word & 0xf800) == 0x6800) {
        const dest = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f) << 2;
        state.write(dest, try readMemory32(state, hooks, state.read(base) + offset));
        return;
    }

    if ((word & 0xf800) == 0x7000) {
        const write8 = hooks.memory.write8 orelse return error.MissingWrite;
        const data = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f);
        write8(state.read(base) + offset, bits.lowByte(state.read(data)));
        return;
    }

    if ((word & 0xf800) == 0x7800) {
        const read8 = hooks.memory.read8 orelse return error.MissingRead;
        const dest = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f);
        state.write(dest, read8(state.read(base) + offset));
        return;
    }

    if ((word & 0xf800) == 0x8000) {
        const data = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f) << 1;
        try writeMemory16(state, hooks, state.read(base) + offset, @intCast(u16, state.read(data) & 0xffff));
        return;
    }

    if ((word & 0xf800) == 0x8800) {
        const dest = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f) << 1;
        state.write(dest, try readMemory16(state, hooks, state.read(base) + offset));
        return;
    }

    if ((word & 0xf800) == 0x9000) {
        const data = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        try writeMemory32(state, hooks, state.read(.sp) + offset, state.read(data));
        return;
    }

    if ((word & 0xf800) == 0x9800) {
        const dest = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        state.write(dest, try readMemory32(state, hooks, state.read(.sp) + offset));
        return;
    }

    if ((word & 0xf800) == 0xa000) {
        const dest = arm_state.lowReg(word >> 8);
        const pc = state.read(.pc);
        state.write(dest, alignDown4(pc + 4) + (@as(u32, word & 0xff) << 2));
        return;
    }

    if ((word & 0xf800) == 0xa800) {
        const dest = arm_state.lowReg(word >> 8);
        const amount = @as(u32, word & 0xff) << 2;
        const result = addWithCarry(state.read(.sp), amount, false);
        state.write(dest, result.word);
        return;
    }

    if ((word & 0xff80) == 0xb000) {
        const amount = @as(u32, word & 0x7f) << 2;
        const result = addWithCarry(state.read(.sp), amount, false);
        state.write(.sp, result.word);
        return;
    }

    if ((word & 0xff80) == 0xb080) {
        const amount = @as(u32, word & 0x7f) << 2;
        const result = subWithCarry(state.read(.sp), amount, true);
        state.write(.sp, result.word);
        return;
    }

    if ((word & 0xfe00) == 0xb400) {
        const mask = pushMask(word);
        const count = bits.countLow16(mask);
        if (count == 0) {
            return error.Unpredictable;
        }
        const final_sp = state.read(.sp) -% (@as(u32, count) << 2);
        var address = final_sp;
        var index: u8 = 0;
        while (index < 16) : (index += 1) {
            if ((mask & (@as(u16, 1) << @intCast(u4, index))) != 0) {
                try writeMemory32(state, hooks, address, state.read(@intToEnum(arm_state.ArmReg, index)));
                address +%= 4;
            }
        }
        state.write(.sp, final_sp);
        return;
    }

    if ((word & 0xfe00) == 0xbc00) {
        const mask = popMask(word);
        const count = bits.countLow16(mask);
        if (count == 0) {
            return error.Unpredictable;
        }
        var address = state.read(.sp);
        var index: u8 = 0;
        while (index < 15) : (index += 1) {
            if ((mask & (@as(u16, 1) << @intCast(u4, index))) != 0) {
                state.write(@intToEnum(arm_state.ArmReg, index), try readMemory32(state, hooks, address));
                address +%= 4;
            }
        }
        if ((mask & (@as(u16, 1) << 15)) != 0) {
            loadWritePc(state, try readMemory32(state, hooks, address));
            address +%= 4;
        }
        state.write(.sp, address);
        return;
    }

    if ((word & 0xfff7) == 0xb650) {
        state.setBigEndian((word & 8) != 0);
        return;
    }

    if ((word & 0xffe8) == 0xb660) {
        return;
    }

    if ((word & 0xf800) == 0xc000) {
        const base = arm_state.lowReg(word >> 8);
        const mask = @intCast(u8, word & 0xff);
        var address = state.read(base);
        var index: u8 = 0;
        while (index < 8) : (index += 1) {
            if ((mask & (@as(u8, 1) << @intCast(u3, index))) != 0) {
                try writeMemory32(state, hooks, address, state.read(@intToEnum(arm_state.ArmReg, index)));
                address +%= 4;
            }
        }
        state.write(base, address);
        return;
    }

    if ((word & 0xf800) == 0xc800) {
        const base = arm_state.lowReg(word >> 8);
        const mask = @intCast(u8, word & 0xff);
        var address = state.read(base);
        var index: u8 = 0;
        while (index < 8) : (index += 1) {
            if ((mask & (@as(u8, 1) << @intCast(u3, index))) != 0) {
                state.write(@intToEnum(arm_state.ArmReg, index), try readMemory32(state, hooks, address));
                address +%= 4;
            }
        }
        if ((mask & (@as(u8, 1) << @intCast(u3, @enumToInt(base)))) == 0) {
            state.write(base, address);
        }
        return;
    }

    if ((word & 0xffc0) == 0xb200) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendHalf(state.read(source)));
        return;
    }

    if ((word & 0xffc0) == 0xb240) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendByte(state.read(source)));
        return;
    }

    if ((word & 0xffc0) == 0xb280) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, state.read(source) & 0xffff);
        return;
    }

    if ((word & 0xffc0) == 0xb2c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, state.read(source) & 0xff);
        return;
    }

    if ((word & 0xffc0) == 0xba00) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, byteReverseWord(state.read(source)));
        return;
    }

    if ((word & 0xffc0) == 0xba40) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, byteReverseHalfwords(state.read(source)));
        return;
    }

    if ((word & 0xffc0) == 0xbac0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendHalf(byteReverseHalf(state.read(source))));
        return;
    }

    if ((word & 0xf000) == 0xd000 and (word & 0x0f00) < 0x0e00) {
        const code = arm_state.conditionFromNibble(@intCast(u4, (word >> 8) & 0xf)).?;
        if (state.conditionHolds(code)) {
            const pc = state.read(.pc);
            const offset = bits.signExtend32(@as(u32, word & 0xff) << 1, 9);
            state.write(.pc, @intCast(u32, @intCast(i32, pc + 4) + offset));
        }
        return;
    }

    if ((word & 0xf800) == 0xe000) {
        state.write(.pc, branchTarget(word, state.read(.pc)).?);
        return;
    }

    return error.UnknownInstruction;
}

