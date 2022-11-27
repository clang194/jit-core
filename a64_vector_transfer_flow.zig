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
usingnamespace @import("a64_vector_table.zig");
usingnamespace @import("a64_count_bits.zig");
usingnamespace @import("a64_memory_bits.zig");

pub const Core64Methods = struct {
    pub fn runAesRound(self: *Core64, word: u32) bool {
        const masked = word & 0xfffffc00;
        if (masked != 0x4e284800 and masked != 0x4e285800 and masked != 0x4e286800 and masked != 0x4e287800) {
            return false;
        }

        const input = if (masked == 0x4e284800 or masked == 0x4e285800) blk: {
            const left = self.state.readVector(vectorRegFromWord(word));
            const right = self.state.readVector(vectorRegFromWord(word >> 5));
            break :blk a64_state.VectorValue{ .low = left.low ^ right.low, .high = left.high ^ right.high };
        } else self.state.readVector(vectorRegFromWord(word >> 5));
        const output = if (masked == 0x4e284800)
            encryptAesVector(input)
        else if (masked == 0x4e285800)
            decryptAesVector(input)
        else
            mixAesVector(input, masked == 0x4e287800);
        self.state.writeVector(vectorRegFromWord(word), output);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runHashRotate(self: *Core64, word: u32) bool {
        if ((word & 0xfffffc00) != 0x5e280800) {
            return false;
        }

        const source = @intCast(u32, self.state.readVector(vectorRegFromWord(word >> 5)).low);
        const result = (source << 30) | (source >> 2);
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = @as(u64, result), .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorTableLookup(self: *Core64, word: u32) bool {
        const masked = word & 0xbfe09c00;
        const replacing = masked == 0x0e001000;
        if (masked != 0x0e000000 and !replacing) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const total = if (full) @as(usize, 16) else @as(usize, 8);
        const count = @as(usize, ((word >> 13) & 3) + 1);
        const first = @intCast(usize, (word >> 5) & 0x1f);
        var table: [4]a64_state.VectorValue = undefined;
        var index: usize = 0;
        while (index < 4) : (index += 1) {
            table[index] = self.state.readVector(@intCast(u5, (first + index) & 0x1f));
        }

        const defaults = if (replacing) self.state.readVector(vectorRegFromWord(word)) else a64_state.VectorValue{ .low = 0, .high = 0 };
        const indices = self.state.readVector(vectorRegFromWord(word >> 16));
        self.state.writeVector(vectorRegFromWord(word), lookupVectorBytes(defaults, table, count, indices, total));
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorDuplicate(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbfe0fc00;
        if (masked != 0x0e000400 and masked != 0x0e000c00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const imm5 = @intCast(u5, (word >> 16) & 0x1f);
        if (imm5 == 0) {
            return error.UnallocatedEncoding;
        }

        const size = lowestSetBit5(imm5);
        if (size > 3) {
            return error.UnallocatedEncoding;
        }
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << size;
        const value = if (masked == 0x0e000c00)
            self.readSized(lane == 64, regFromWord(word >> 5), false) & ones(lane)
        else
            vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), @as(usize, imm5) >> (@as(usize, size) + 1), @as(usize, lane) / 8);
        const half = spreadVectorElement(value, lane);
        const result = a64_state.VectorValue{
            .low = half,
            .high = if (full) half else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarDuplicate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xffe0fc00) != 0x5e000400) {
            return false;
        }

        const imm5 = @intCast(u5, (word >> 16) & 0x1f);
        if (imm5 == 0) {
            return error.UnallocatedEncoding;
        }

        const size = lowestSetBit5(imm5);
        if (size > 3) {
            return error.UnallocatedEncoding;
        }

        const bytes = @as(usize, 1) << size;
        const index = @as(usize, imm5) >> @intCast(u3, size + 1);
        const element = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), index, bytes);
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = element, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarIntegerToFloat(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xffbffc00;
        const signed = masked == 0x5e21d800;
        const unsigned = masked == 0x7e21d800;
        if (!signed and !unsigned) {
            return false;
        }

        const double = (word & 0x00400000) != 0;
        const source = self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const control = self.state.floatControl();
        const result = if (double)
            if (signed) signedDoublewordToFloat64(source) else unsignedDoublewordToFloat64(control, source)
        else
            @as(u64, if (signed) signedWordToFloat32(@intCast(u32, source)) else unsignedWordToFloat32(@intCast(u32, source)));
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = @as(u64, result), .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorExtractToRegister(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbfe0fc00;
        if (masked != 0x0e002c00 and masked != 0x0e003c00) {
            return false;
        }

        const signed = masked == 0x0e002c00;
        const wide = (word & 0x40000000) != 0;
        const imm5 = @intCast(u5, (word >> 16) & 0x1f);
        if (imm5 == 0) {
            return error.UnallocatedEncoding;
        }

        const size = lowestSetBit5(imm5);
        if (signed) {
            if ((size == 2 and !wide) or size > 2) {
                return error.UnallocatedEncoding;
            }
        } else {
            if ((size < 3 and wide) or (size == 3 and !wide) or size > 3) {
                return error.UnallocatedEncoding;
            }
        }

        const bytes = @as(usize, 1) << size;
        const index = @as(usize, imm5) >> @intCast(u3, size + 1);
        const element = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), index, bytes);
        const value = if (signed) signExtendRuntime(element, @intCast(u6, bytes * 8)) else element;
        self.writeSized(wide, regFromWord(word), value, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorWidenLongShift(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf3ffc00) != 0x2e213800) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const half = if ((word & 0x40000000) != 0) source.high else source.low;
        self.state.writeVector(vectorRegFromWord(word), widenShiftLeftVectorHalf(half, lane, @intCast(u6, lane)));
        self.state.pc +%= 4;
        return true;
    }

    pub fn runRegisterInsertElement(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xffe0fc00) != 0x4e001c00) {
            return false;
        }

        const imm5 = @intCast(u5, (word >> 16) & 0x1f);
        if (imm5 == 0) {
            return error.UnallocatedEncoding;
        }

        const size = lowestSetBit5(imm5);
        if (size > 3) {
            return error.UnallocatedEncoding;
        }

        const bytes = @as(usize, 1) << size;
        const index = @as(usize, imm5) >> @intCast(u3, size + 1);
        const element = self.readSized(bytes == 8, regFromWord(word >> 5), false);
        var result = self.state.readVector(vectorRegFromWord(word));
        setVectorElement(&result, index, bytes, element);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorInsertElement(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xffe08400) != 0x6e000400) {
            return false;
        }

        const imm5 = @intCast(u5, (word >> 16) & 0x1f);
        if (imm5 == 0) {
            return error.UnallocatedEncoding;
        }

        const size = lowestSetBit5(imm5);
        if (size > 3) {
            return error.UnallocatedEncoding;
        }

        const bytes = @as(usize, 1) << size;
        const target_index = @as(usize, imm5) >> @intCast(u3, size + 1);
        const source_index = @as(usize, (word >> 11) & 0xf) >> size;
        const element = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), source_index, bytes);
        var result = self.state.readVector(vectorRegFromWord(word));
        setVectorElement(&result, target_index, bytes, element);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorModifiedImmediate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbff8fc00) == 0x0f00fc00) {
            const full = (word & 0x40000000) != 0;
            const imm8 = @intCast(u8, ((word >> 11) & 0xe0) | ((word >> 5) & 0x1f));
            const expanded = expandVectorHalfFloatImmediate(imm8);
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{
                .low = expanded,
                .high = if (full) expanded else 0,
            });
            self.state.pc +%= 4;
            return true;
        }

        if ((word & 0x9ff80c00) == 0x0f000c00) {
            return error.UnallocatedEncoding;
        }

        if ((word & 0x9ff80c00) != 0x0f000400) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const op = (word & 0x20000000) != 0;
        const cmode = @intCast(u4, (word >> 12) & 0xf);
        const imm8 = @intCast(u8, ((word >> 11) & 0xe0) | ((word >> 5) & 0x1f));
        const selector = (@as(u5, cmode) << 1) | @as(u5, if (op) 1 else 0);
        const expanded = expandVectorImmediate(op, cmode, imm8);
        const immediate = a64_state.VectorValue{
            .low = expanded,
            .high = if (full) expanded else 0,
        };
        const dest = vectorRegFromWord(word);
        const prior = self.state.readVector(dest);
        const result = switch (selector) {
            0, 4, 8, 12, 16, 20, 24, 26, 28, 29, 30 => immediate,
            31 => blk: {
                if (!full) {
                    return error.UnallocatedEncoding;
                }
                break :blk immediate;
            },
            1, 5, 9, 13, 17, 21, 25, 27 => a64_state.VectorValue{
                .low = ~expanded,
                .high = if (full) ~expanded else 0,
            },
            2, 6, 10, 14, 18, 22 => a64_state.VectorValue{
                .low = prior.low | expanded,
                .high = if (full) prior.high | expanded else 0,
            },
            3, 7, 11, 15, 19, 23 => a64_state.VectorValue{
                .low = prior.low & ~expanded,
                .high = if (full) prior.high & ~expanded else 0,
            },
            else => return error.UnallocatedEncoding,
        };
        self.state.writeVector(dest, result);
        self.state.pc +%= 4;
        return true;
    }
};
