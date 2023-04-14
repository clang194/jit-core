const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
const thumb_decode = @import("thumb_fetch_decode.zig");
const RunError = thumb_decode.RunError;
const thumb_memory = @import("thumb_memory_flow.zig");
const alignDown4 = thumb_memory.alignDown4;
const thumb_reverse = @import("thumb_masks_reverse.zig");
const popMask = thumb_reverse.popMask;
const pushMask = thumb_reverse.pushMask;
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");
usingnamespace @import("thumb_memory_flow.zig");

pub fn traceThumbMemoryFlow(word: u16, pc: u32, tape: *trace.Tape) RunError!bool {
    if ((word & 0xf800) == 0x4800) {
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        const address = try tape.literalWord(alignDown4(pc + 4) + (@as(u32, word & 0xff) << 2));
        const data = try tape.readWord(address);
        _ = try tape.storeReg(dest, data);
        return true;
    }

    if ((word & 0xfe00) == 0x5000) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const data_reg = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.loadReg(data_reg);
        _ = try tape.writeWord(address, data);
        return true;
    }

    if ((word & 0xfe00) == 0x5200) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const data_reg = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.lowHalf(try tape.loadReg(data_reg));
        _ = try tape.writeHalf(address, data);
        return true;
    }

    if ((word & 0xfe00) == 0x5400) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const data_reg = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.lowByte(try tape.loadReg(data_reg));
        _ = try tape.writeByte(address, data);
        return true;
    }

    if ((word & 0xfe00) == 0x5600) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.readByte(address);
        _ = try tape.storeReg(dest, try tape.signExtendByte(data));
        return true;
    }

    if ((word & 0xfe00) == 0x5800) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        _ = try tape.storeReg(dest, try tape.readWord(address));
        return true;
    }

    if ((word & 0xfe00) == 0x5a00) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.readHalf(address);
        _ = try tape.storeReg(dest, try tape.zeroExtendHalf(data));
        return true;
    }

    if ((word & 0xfe00) == 0x5c00) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.readByte(address);
        _ = try tape.storeReg(dest, try tape.zeroExtendByte(data));
        return true;
    }

    if ((word & 0xfe00) == 0x5e00) {
        const source_reg = try tape.literalReg(arm_state.lowReg(word >> 6));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const offset = try tape.loadReg(source_reg);
        const address = try tape.wordAdd(base, offset);
        const data = try tape.readHalf(address);
        _ = try tape.storeReg(dest, try tape.signExtendHalf(data));
        return true;
    }

    if ((word & 0xf800) == 0x6000) {
        const amount = try tape.literalWord(@as(u32, (word >> 6) & 0x1f) << 2);
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const data_reg = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.loadReg(data_reg);
        _ = try tape.writeWord(address, data);
        return true;
    }

    if ((word & 0xf800) == 0x6800) {
        const amount = try tape.literalWord(@as(u32, (word >> 6) & 0x1f) << 2);
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.readWord(address);
        _ = try tape.storeReg(dest, data);
        return true;
    }

    if ((word & 0xf800) == 0x7000) {
        const amount = try tape.literalWord(@as(u32, (word >> 6) & 0x1f));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const data_reg = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.lowByte(try tape.loadReg(data_reg));
        _ = try tape.writeByte(address, data);
        return true;
    }

    if ((word & 0xf800) == 0x7800) {
        const amount = try tape.literalWord(@as(u32, (word >> 6) & 0x1f));
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.readByte(address);
        _ = try tape.storeReg(dest, try tape.zeroExtendByte(data));
        return true;
    }

    if ((word & 0xf800) == 0x8000) {
        const amount = try tape.literalWord(@as(u32, (word >> 6) & 0x1f) << 1);
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const data_reg = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.lowHalf(try tape.loadReg(data_reg));
        _ = try tape.writeHalf(address, data);
        return true;
    }

    if ((word & 0xf800) == 0x8800) {
        const amount = try tape.literalWord(@as(u32, (word >> 6) & 0x1f) << 1);
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 3));
        const dest = try tape.literalReg(arm_state.lowReg(word));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.readHalf(address);
        _ = try tape.storeReg(dest, try tape.zeroExtendHalf(data));
        return true;
    }

    if ((word & 0xf800) == 0x9000) {
        const amount = try tape.literalWord(@as(u32, word & 0xff) << 2);
        const base_reg = try tape.literalReg(.sp);
        const data_reg = try tape.literalReg(arm_state.lowReg(word >> 8));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        const data = try tape.loadReg(data_reg);
        _ = try tape.writeWord(address, data);
        return true;
    }

    if ((word & 0xf800) == 0x9800) {
        const amount = try tape.literalWord(@as(u32, word & 0xff) << 2);
        const base_reg = try tape.literalReg(.sp);
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        const base = try tape.loadReg(base_reg);
        const address = try tape.wordAdd(base, amount);
        _ = try tape.storeReg(dest, try tape.readWord(address));
        return true;
    }

    if ((word & 0xf800) == 0xa000) {
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        const base = try tape.literalWord(alignDown4(pc + 4));
        const amount = try tape.literalWord(@as(u32, word & 0xff) << 2);
        _ = try tape.storeReg(dest, try tape.wordAdd(base, amount));
        return true;
    }

    if ((word & 0xf800) == 0xa800) {
        const dest = try tape.literalReg(arm_state.lowReg(word >> 8));
        const base_reg = try tape.literalReg(.sp);
        const base = try tape.loadReg(base_reg);
        const amount = try tape.literalWord(@as(u32, word & 0xff) << 2);
        const carry_in = try tape.literalBit(false);
        _ = try tape.storeReg(dest, try tape.addCarrying(base, amount, carry_in));
        return true;
    }

    if ((word & 0xff80) == 0xb000) {
        const dest = try tape.literalReg(.sp);
        const base = try tape.loadReg(dest);
        const amount = try tape.literalWord(@as(u32, word & 0x7f) << 2);
        const carry_in = try tape.literalBit(false);
        _ = try tape.storeReg(dest, try tape.addCarrying(base, amount, carry_in));
        return true;
    }

    if ((word & 0xff80) == 0xb080) {
        const dest = try tape.literalReg(.sp);
        const base = try tape.loadReg(dest);
        const amount = try tape.literalWord(@as(u32, word & 0x7f) << 2);
        const carry_in = try tape.literalBit(true);
        _ = try tape.storeReg(dest, try tape.subCarrying(base, amount, carry_in));
        return true;
    }

    if ((word & 0xfe00) == 0xb400) {
        const mask = pushMask(word);
        const count = bits.countLow16(mask);
        if (count == 0) {
            return error.Unpredictable;
        }
        const sp_reg = try tape.literalReg(.sp);
        const old_sp = try tape.loadReg(sp_reg);
        const amount = try tape.literalWord(@as(u32, count) << 2);
        const carry_in = try tape.literalBit(true);
        const final_sp = try tape.subCarrying(old_sp, amount, carry_in);
        var address = final_sp;
        var index: u8 = 0;
        while (index < 16) : (index += 1) {
            if ((mask & (@as(u16, 1) << @intCast(u4, index))) != 0) {
                const reg = try tape.literalReg(@intToEnum(arm_state.ArmReg, index));
                const value = try tape.loadReg(reg);
                _ = try tape.writeWord(address, value);
                address = try tape.wordAdd(address, try tape.literalWord(4));
            }
        }
        _ = try tape.storeReg(sp_reg, final_sp);
        return true;
    }

    if ((word & 0xfe00) == 0xbc00) {
        const mask = popMask(word);
        const count = bits.countLow16(mask);
        if (count == 0) {
            return error.Unpredictable;
        }
        const sp_reg = try tape.literalReg(.sp);
        var address = try tape.loadReg(sp_reg);
        var index: u8 = 0;
        while (index < 15) : (index += 1) {
            if ((mask & (@as(u16, 1) << @intCast(u4, index))) != 0) {
                const reg = try tape.literalReg(@intToEnum(arm_state.ArmReg, index));
                const data = try tape.readWord(address);
                _ = try tape.storeReg(reg, data);
                address = try tape.wordAdd(address, try tape.literalWord(4));
            }
        }
        if ((mask & (@as(u16, 1) << 15)) != 0) {
            const data = try tape.readWord(address);
            _ = try tape.loadPc(data);
            address = try tape.wordAdd(address, try tape.literalWord(4));
        }
        _ = try tape.storeReg(sp_reg, address);
        return true;
    }

    if ((word & 0xfff7) == 0xb650) {
        _ = try tape.storeEndian(try tape.literalBit((word & 8) != 0));
        return true;
    }

    if ((word & 0xf800) == 0xc000) {
        const base_reg = try tape.literalReg(arm_state.lowReg(word >> 8));
        var address = try tape.loadReg(base_reg);
        const mask = @intCast(u8, word & 0xff);
        if (mask == 0) {
            return error.Unpredictable;
        }
        const base = arm_state.lowReg(word >> 8);
        if ((mask & (@as(u8, 1) << @intCast(u3, @enumToInt(base)))) != 0 and @intCast(u4, @enumToInt(base)) != bits.firstSetLow8(mask)) {
            return error.Unpredictable;
        }
        var index: u8 = 0;
        while (index < 8) : (index += 1) {
            if ((mask & (@as(u8, 1) << @intCast(u3, index))) != 0) {
                const data_reg = try tape.literalReg(@intToEnum(arm_state.ArmReg, index));
                const data = try tape.loadReg(data_reg);
                _ = try tape.writeWord(address, data);
                address = try tape.wordAdd(address, try tape.literalWord(4));
            }
        }
        _ = try tape.storeReg(base_reg, address);
        return true;
    }

    if ((word & 0xf800) == 0xc800) {
        const base = arm_state.lowReg(word >> 8);
        const base_reg = try tape.literalReg(base);
        var address = try tape.loadReg(base_reg);
        const mask = @intCast(u8, word & 0xff);
        if (mask == 0) {
            return error.Unpredictable;
        }
        var index: u8 = 0;
        while (index < 8) : (index += 1) {
            if ((mask & (@as(u8, 1) << @intCast(u3, index))) != 0) {
                const dest = try tape.literalReg(@intToEnum(arm_state.ArmReg, index));
                const data = try tape.readWord(address);
                _ = try tape.storeReg(dest, data);
                address = try tape.wordAdd(address, try tape.literalWord(4));
            }
        }
        if ((mask & (@as(u8, 1) << @intCast(u3, @enumToInt(base)))) == 0) {
            _ = try tape.storeReg(base_reg, address);
        }
        return true;
    }
    return false;
}
