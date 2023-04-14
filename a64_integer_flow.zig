const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const Core64 = main.Core64;
const Core64Error = main.Core64Error;
const FaultKind64 = main.FaultKind64;
const CacheAction64 = main.CacheAction64;
const FloatNanMode64 = main.FloatNanMode64;
const HostHooks64 = main.HostHooks64;
usingnamespace @import("a64_math_flags.zig");
usingnamespace @import("a64_logic_masks.zig");
usingnamespace @import("a64_immediate_vectors.zig");
usingnamespace @import("a64_divide_crc.zig");
usingnamespace @import("a64_crypto_tables.zig");
usingnamespace @import("a64_float_control.zig");
usingnamespace @import("a64_float_arithmetic.zig");
usingnamespace @import("a64_float_minmax.zig");
usingnamespace @import("a64_float_nan.zig");
usingnamespace @import("a64_vector_access.zig");
usingnamespace @import("a64_crypto_vectors.zig");
usingnamespace @import("a64_vector_integer.zig");
usingnamespace @import("a64_vector_float.zig");
usingnamespace @import("a64_vector_compare.zig");
usingnamespace @import("a64_vector_shift.zig");
usingnamespace @import("a64_count_bits.zig");
usingnamespace @import("a64_memory_bits.zig");

pub const Core64Methods = struct {
    pub fn runLogicalImmediate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1f800000) != 0x12000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const opcode = @intCast(u2, (word >> 29) & 3);
        const n = (word & 0x00400000) != 0;
        if (!wide and n) {
            return error.ReservedInstruction;
        }
        const immediate = decodeLogicalMask(n, @intCast(u6, (word >> 10) & 0x3f), @intCast(u6, (word >> 16) & 0x3f)) orelse return error.ReservedInstruction;
        const dest = regFromWord(word);
        const left = self.readSized(wide, regFromWord(word >> 5), false);
        const result = logicalOp(wide, opcode, left, immediate, false);
        if (opcode == 3) {
            self.writeLogicalNzcv(wide, result);
            self.writeSized(wide, dest, result, false);
        } else {
            self.writeSized(wide, dest, result, dest == .sp);
        }
        self.state.pc +%= 4;
        return true;
    }

    pub fn runLogicalShifted(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1f000000) != 0x0a000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const opcode = @intCast(u2, (word >> 29) & 3);
        const invert = (word & 0x00200000) != 0;
        const amount = @intCast(u6, (word >> 10) & 0x3f);
        if (!wide and (amount & 0x20) != 0) {
            return error.ReservedInstruction;
        }

        const left = self.readSized(wide, regFromWord(word >> 5), false);
        const right = self.shiftedReg(wide, regFromWord(word >> 16), @intCast(u2, (word >> 22) & 3), amount);
        const result = logicalOp(wide, opcode, left, right, invert);
        const dest = regFromWord(word);
        if (opcode == 3) {
            self.writeLogicalNzcv(wide, result);
        }
        self.writeSized(wide, dest, result, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runAddSubImmediate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1f000000) != 0x11000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const subtract = (word & 0x40000000) != 0;
        const flags = (word & 0x20000000) != 0;
        const shift = @intCast(u2, (word >> 22) & 3);
        if (shift > 1) {
            return error.ReservedInstruction;
        }

        var immediate = @as(u64, (word >> 10) & 0xfff);
        if (shift == 1) {
            immediate <<= 12;
        }

        const source = regFromWord(word >> 5);
        const dest = regFromWord(word);
        const left = self.readSized(wide, source, true);
        const result = if (subtract) mathSub(wide, left, immediate, true) else mathAdd(wide, left, immediate, false);
        if (flags) {
            self.writeNzcv(wide, result);
            self.writeSized(wide, dest, result.word, false);
        } else {
            self.writeSized(wide, dest, result.word, true);
        }
        self.state.pc +%= 4;
        return true;
    }

    pub fn runAddShifted(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1f200000) != 0x0b000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const subtract = (word & 0x40000000) != 0;
        const flags = (word & 0x20000000) != 0;
        const shift = @intCast(u2, (word >> 22) & 3);
        const amount = @intCast(u6, (word >> 10) & 0x3f);
        if (shift == 3 or (!wide and (amount & 0x20) != 0)) {
            return error.ReservedInstruction;
        }

        const source = regFromWord(word >> 5);
        const shifted = self.shiftedReg(wide, regFromWord(word >> 16), shift, amount);
        const dest = regFromWord(word);
        const left = self.readSized(wide, source, false);
        const result = if (subtract) mathSub(wide, left, shifted, true) else mathAdd(wide, left, shifted, false);

        if (flags) {
            self.writeNzcv(wide, result);
            self.writeSized(wide, dest, result.word, false);
        } else {
            self.writeSized(wide, dest, result.word, false);
        }
        self.state.pc +%= 4;
        return true;
    }

    pub fn shiftedReg(self: *const Core64, wide: bool, reg: a64_state.GeneralReg, shift: u2, amount: u6) u64 {
        const value = self.readSized(wide, reg, false);
        if (wide) {
            return shift64(value, shift, amount);
        }
        return @as(u64, shift32(@intCast(u32, value), shift, @intCast(u5, amount)));
    }

    pub fn runAddSubExtended(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1fe00000) != 0x0b200000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const subtract = (word & 0x40000000) != 0;
        const flags = (word & 0x20000000) != 0;
        const amount = @intCast(u3, (word >> 10) & 7);
        if (amount > 4) {
            return error.ReservedInstruction;
        }

        const source = regFromWord(word >> 5);
        const extended = self.extendedReg(wide, regFromWord(word >> 16), @intCast(u3, (word >> 13) & 7), amount);
        const dest = regFromWord(word);
        const left = self.readSized(wide, source, true);
        const result = if (subtract) mathSub(wide, left, extended, true) else mathAdd(wide, left, extended, false);

        if (flags) {
            self.writeNzcv(wide, result);
            self.writeSized(wide, dest, result.word, false);
        } else {
            self.writeSized(wide, dest, result.word, true);
        }
        self.state.pc +%= 4;
        return true;
    }

    pub fn runAddSubCarry(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1fe0fc00) != 0x1a000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const subtract = (word & 0x40000000) != 0;
        const flags = (word & 0x20000000) != 0;
        const left = self.readSized(wide, regFromWord(word >> 5), false);
        const right = self.readSized(wide, regFromWord(word >> 16), false);
        const result = if (subtract) mathSub(wide, left, right, self.state.carry()) else mathAdd(wide, left, right, self.state.carry());
        if (flags) {
            self.writeNzcv(wide, result);
        }
        self.writeSized(wide, regFromWord(word), result.word, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runWideMove(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1f800000) != 0x12800000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const opcode = @intCast(u2, (word >> 29) & 3);
        if (opcode == 1) {
            return error.UnallocatedEncoding;
        }

        const half = @intCast(u2, (word >> 21) & 3);
        if (!wide and (half & 2) != 0) {
            return error.UnallocatedEncoding;
        }

        const shift = @as(u6, half) * 16;
        const dest = regFromWord(word);
        const value = @as(u64, (word >> 5) & 0xffff) << shift;
        const mask = @as(u64, 0xffff) << shift;
        const result = switch (opcode) {
            0 => ~value,
            2 => value,
            else => (self.readSized(wide, dest, false) & ~mask) | value,
        };
        self.writeSized(wide, dest, result, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runBitfieldMove(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1f800000) != 0x13000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const opcode = @intCast(u2, (word >> 29) & 3);
        if (opcode == 3) {
            return error.UnallocatedEncoding;
        }

        const n = (word & 0x00400000) != 0;
        const rotate = @intCast(u6, (word >> 16) & 0x3f);
        const last = @intCast(u6, (word >> 10) & 0x3f);
        if ((wide and !n) or (!wide and (n or (rotate & 0x20) != 0 or (last & 0x20) != 0))) {
            return error.ReservedInstruction;
        }

        if (opcode == 0 and last == if (wide) @as(u6, 63) else @as(u6, 31)) {
            const source = self.readSized(wide, regFromWord(word >> 5), false);
            const result = if (wide)
                bits.signedShiftRight64(source, @intCast(i32, rotate))
            else
                @as(u64, bits.signedShiftRight32(@intCast(u32, source), @intCast(i32, rotate)));
            self.writeSized(wide, regFromWord(word), result, false);
            self.state.pc +%= 4;
            return true;
        }

        if (opcode == 0 and rotate == 0 and wide and last == 31) {
            const source = self.readSized(true, regFromWord(word >> 5), false);
            self.writeSized(true, regFromWord(word), @bitCast(u64, bits.signExtend64(source & 0xffffffff, 32)), false);
            self.state.pc +%= 4;
            return true;
        }

        if (opcode == 0 and rotate == 0 and (last == 7 or last == 15)) {
            const source = self.readSized(wide, regFromWord(word >> 5), false);
            const result = if (last == 7)
                if (wide)
                    @bitCast(u64, bits.signExtend64(source & 0xff, 8))
                else
                    @as(u64, @bitCast(u32, bits.signExtend32(@intCast(u32, source & 0xff), 8)))
            else if (wide)
                @bitCast(u64, bits.signExtend64(source & 0xffff, 16))
            else
                @as(u64, @bitCast(u32, bits.signExtend32(@intCast(u32, source & 0xffff), 16)));
            self.writeSized(wide, regFromWord(word), result, false);
            self.state.pc +%= 4;
            return true;
        }

        const masks = decodeBitPattern(n, last, rotate, false) orelse return error.ReservedInstruction;
        const source = self.readSized(wide, regFromWord(word >> 5), false);
        const rotated = rotateRightSized(wide, source, rotate);
        const dest = regFromWord(word);
        const result = switch (opcode) {
            0 => blk: {
                const fill = bits.maskFromSetBit64(source, last);
                break :blk (fill & ~masks.limit) | (rotated & masks.write & masks.limit);
            },
            1 => blk: {
                const prior = self.readSized(wide, dest, false);
                const bottom = (prior & ~masks.write) | (rotated & masks.write);
                break :blk (prior & ~masks.limit) | (bottom & masks.limit);
            },
            else => rotated & masks.write & masks.limit,
        };
        self.writeSized(wide, dest, result, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runExtractRegister(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x7fa00000) != 0x13800000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const n = (word & 0x00400000) != 0;
        if (n != wide) {
            return error.UnallocatedEncoding;
        }

        const amount = @intCast(u6, (word >> 10) & 0x3f);
        if (!wide and (amount & 0x20) != 0) {
            return error.ReservedInstruction;
        }

        const lower = self.readSized(wide, regFromWord(word >> 16), false);
        const upper = self.readSized(wide, regFromWord(word >> 5), false);
        self.writeSized(wide, regFromWord(word), extractRegisterBits(wide, lower, upper, amount), false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runConditionalSelect(self: *Core64, word: u32) bool {
        if ((word & 0x3fe00800) != 0x1a800000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const fallback = self.readSized(wide, regFromWord(word >> 16), false);
        const altered = switch (@intCast(u2, ((word >> 29) & 2) | ((word >> 10) & 1))) {
            0 => fallback,
            1 => fallback +% 1,
            2 => ~fallback,
            else => ~fallback +% 1,
        };
        const value = if (self.conditionHolds(@intCast(u4, (word >> 12) & 0xf)))
            self.readSized(wide, regFromWord(word >> 5), false)
        else
            altered;
        self.writeSized(wide, regFromWord(word), value, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runConditionalCompare(self: *Core64, word: u32) bool {
        const masked = word & 0x7fe00c10;
        if (masked != 0x3a400000 and masked != 0x7a400000 and masked != 0x3a400800 and masked != 0x7a400800) {
            return false;
        }

        if (self.conditionHolds(@intCast(u4, (word >> 12) & 0xf))) {
            const wide = (word & 0x80000000) != 0;
            const left = self.readSized(wide, regFromWord(word >> 5), false);
            const right = if ((masked & 0x800) != 0) @as(u64, (word >> 16) & 0x1f) else self.readSized(wide, regFromWord(word >> 16), false);
            const result = if ((masked & 0x40000000) != 0) mathSub(wide, left, right, true) else mathAdd(wide, left, right, false);
            self.writeNzcv(wide, result);
        } else {
            self.state.writeNzcv(@as(u32, word & 0xf) << 28);
        }
        self.state.pc +%= 4;
        return true;
    }

    pub fn runByteReverse(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xfffffc00;
        const wide = (word & 0x80000000) != 0;
        const source = self.readSized(wide, regFromWord(word >> 5), false);
        const result = if ((masked & 0x7fffffff) == 0x5ac00000)
            if (wide) reverseBits64(source) else @as(u64, reverseBits32(@intCast(u32, source)))
        else if ((masked & 0x7fffffff) == 0x5ac00400)
            reverseHalfBytes(source)
        else if (masked == 0xdac00800)
            (@as(u64, reverseBytes32(@intCast(u32, source >> 32))) << 32) | @as(u64, reverseBytes32(@intCast(u32, source)))
        else if (masked == 0x5ac00800)
            @as(u64, reverseBytes32(@intCast(u32, source)))
        else if (masked == 0xdac00c00)
            reverseBytes64(source)
        else if (masked == 0x5ac00c00)
            return error.UnallocatedEncoding
        else
            return false;
        self.writeSized(wide, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }
};
