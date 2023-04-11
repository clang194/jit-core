const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");
usingnamespace @import("thumb_memory_flow.zig");

pub fn runThumbStackBranchFlow(word: u16, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!bool {
    if ((word & 0xf800) == 0xa000) {
        const dest = arm_state.lowReg(word >> 8);
        const pc = state.read(.pc);
        state.write(dest, alignDown4(pc + 4) + (@as(u32, word & 0xff) << 2));
        return true;
    }

    if ((word & 0xf800) == 0xa800) {
        const dest = arm_state.lowReg(word >> 8);
        const amount = @as(u32, word & 0xff) << 2;
        const result = addWithCarry(state.read(.sp), amount, false);
        state.write(dest, result.word);
        return true;
    }

    if ((word & 0xff80) == 0xb000) {
        const amount = @as(u32, word & 0x7f) << 2;
        const result = addWithCarry(state.read(.sp), amount, false);
        state.write(.sp, result.word);
        return true;
    }

    if ((word & 0xff80) == 0xb080) {
        const amount = @as(u32, word & 0x7f) << 2;
        const result = subWithCarry(state.read(.sp), amount, true);
        state.write(.sp, result.word);
        return true;
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
        return true;
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
        return true;
    }

    if ((word & 0xfff7) == 0xb650) {
        if (!hooks.keep_little_endian) {
            state.setBigEndian((word & 8) != 0);
        }
        return true;
    }

    if ((word & 0xffe8) == 0xb660) {
        return true;
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
        return true;
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
        return true;
    }

    if ((word & 0xffc0) == 0xb200) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendHalf(state.read(source)));
        return true;
    }

    if ((word & 0xffc0) == 0xb240) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendByte(state.read(source)));
        return true;
    }

    if ((word & 0xffc0) == 0xb280) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, state.read(source) & 0xffff);
        return true;
    }

    if ((word & 0xffc0) == 0xb2c0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, state.read(source) & 0xff);
        return true;
    }

    if ((word & 0xffc0) == 0xba00) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, byteReverseWord(state.read(source)));
        return true;
    }

    if ((word & 0xffc0) == 0xba40) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, byteReverseHalfwords(state.read(source)));
        return true;
    }

    if ((word & 0xffc0) == 0xbac0) {
        const source = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendHalf(byteReverseHalf(state.read(source))));
        return true;
    }

    if ((word & 0xf000) == 0xd000 and (word & 0x0f00) < 0x0e00) {
        const code = arm_state.conditionFromNibble(@intCast(u4, (word >> 8) & 0xf)).?;
        if (state.conditionHolds(code)) {
            const pc = state.read(.pc);
            const offset = bits.signExtend32(@as(u32, word & 0xff) << 1, 9);
            state.write(.pc, @intCast(u32, @intCast(i32, pc + 4) + offset));
        }
        return true;
    }

    if ((word & 0xf800) == 0xe000) {
        state.write(.pc, branchTarget(word, state.read(.pc)).?);
        return true;
    }
    return false;
}
