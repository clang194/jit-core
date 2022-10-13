const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const float_status = @import("float_status.zig");
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
    pub fn runVectorExtract(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfe08400) != 0x2e000000) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const start = @intCast(usize, (word >> 11) & 0xf);
        if (!full and (start & 8) != 0) {
            return error.UnallocatedEncoding;
        }

        const total = if (full) @as(usize, 16) else @as(usize, 8);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        self.state.writeVector(vectorRegFromWord(word), extractVectorBytes(left, right, start, total));
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorInterleave(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const unzip_lower = masked == 0x0e001800;
        const lower = masked == 0x0e003800;
        const transpose_lower = masked == 0x0e002800;
        const unzip_upper = masked == 0x0e005800;
        const transpose_upper = masked == 0x0e006800;
        const upper = masked == 0x0e007800;
        if (!unzip_lower and !lower and !transpose_lower and !unzip_upper and !transpose_upper and !upper) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const bytes = @as(usize, 1) << size;
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const total = if (full) @as(usize, 16) else @as(usize, 8);
        const result = if (unzip_lower) unzipLowerVector(left, right, bytes, total) else if (lower) interleaveLowerVector(left, right, bytes, total) else if (transpose_lower) transposeLowerVector(left, right, bytes, total) else if (unzip_upper) unzipUpperVector(left, right, bytes, total) else if (transpose_upper) transposeUpperVector(left, right, bytes, total) else interleaveUpperVector(left, right, bytes, total);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorNarrow(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf3ffc00) != 0x0e212800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3) {
            return error.ReservedInstruction;
        }

        const bytes = @as(usize, 1) << size;
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const narrowed = narrowVectorLanes(source, bytes);
        const result = if (full) blk: {
            var target = self.state.readVector(vectorRegFromWord(word));
            target.high = narrowed;
            break :blk target;
        } else a64_state.VectorValue{ .low = narrowed, .high = 0 };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorSignedSaturatingNarrowUnsigned(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf3ffc00) != 0x2e212800) {
            return false;
        }

        const upper = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3) {
            return error.ReservedInstruction;
        }

        const target_bytes = @as(usize, 1) << size;
        const source_bytes = target_bytes * 2;
        const source_bits = @intCast(u6, source_bytes * 8);
        const target_bits = @intCast(u8, target_bytes * 8);
        const high = @bitCast(i64, ones(target_bits));
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        var narrowed = a64_state.VectorValue{ .low = 0, .high = 0 };
        var saturated = false;
        var index: usize = 0;
        while (index < 8 / target_bytes) : (index += 1) {
            const signed = @bitCast(i64, signExtendRuntime(vectorElement(source, index, source_bytes), source_bits));
            const clamped = if (signed < 0) @as(u64, 0) else if (signed > high) blk: {
                saturated = true;
                break :blk @as(u64, @bitCast(u64, high));
            } else @intCast(u64, signed);
            if (signed < 0) {
                saturated = true;
            }
            setVectorElement(&narrowed, index, target_bytes, clamped);
        }

        if (saturated) {
            var status = float_status.FloatStatus.init(self.state.floatStatus());
            status.setSaturated(true);
            self.state.writeFloatStatus(status.raw());
        }
        const result = if (upper) a64_state.VectorValue{ .low = self.state.readVector(vectorRegFromWord(word)).low, .high = narrowed.low } else a64_state.VectorValue{ .low = narrowed.low, .high = 0 };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorCount(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf3ffc00) != 0x0e205800) {
            return false;
        }

        if (((word >> 22) & 3) != 0) {
            return error.ReservedInstruction;
        }

        const full = (word & 0x40000000) != 0;
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = a64_state.VectorValue{
            .low = countVectorBytes(source.low),
            .high = if (full) countVectorBytes(source.high) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorReverseBits(self: *Core64, word: u32) bool {
        if ((word & 0xbffffc00) != 0x2e605800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{
            .low = reverseVectorByteBits(source.low),
            .high = if (full) reverseVectorByteBits(source.high) else 0,
        });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorReverseHalfBytes(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf3ffc00) != 0x0e201800) {
            return false;
        }

        if (((word >> 22) & 3) != 0) {
            return error.UnallocatedEncoding;
        }

        const full = (word & 0x40000000) != 0;
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = a64_state.VectorValue{
            .low = reverseHalfBytes(source.low),
            .high = if (full) reverseHalfBytes(source.high) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorReverseWordBytes(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf3ffc00) != 0x2e200800) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size > 1) {
            return error.UnallocatedEncoding;
        }

        const full = (word & 0x40000000) != 0;
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = if (size == 0) a64_state.VectorValue{
            .low = reverseWordBytes(source.low),
            .high = if (full) reverseWordBytes(source.high) else 0,
        } else a64_state.VectorValue{
            .low = reverseWordHalfwords(source.low),
            .high = if (full) reverseWordHalfwords(source.high) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorReverseDoublewordBytes(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf3ffc00) != 0x0e200800) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3) {
            return error.UnallocatedEncoding;
        }

        const full = (word & 0x40000000) != 0;
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = switch (size) {
            0 => a64_state.VectorValue{
                .low = reverseBytes64(source.low),
                .high = if (full) reverseBytes64(source.high) else 0,
            },
            1 => a64_state.VectorValue{
                .low = reverseDoublewordHalfwords(source.low),
                .high = if (full) reverseDoublewordHalfwords(source.high) else 0,
            },
            else => a64_state.VectorValue{
                .low = reverseDoublewordWords(source.low),
                .high = if (full) reverseDoublewordWords(source.high) else 0,
            },
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorCompareZero(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf3ffc00;
        const greater = masked == 0x0e208800;
        const greater_equal = masked == 0x2e208800;
        const equal = masked == 0x0e209800;
        const less = masked == 0x0e20a800;
        const less_equal = masked == 0x2e209800;
        if (!greater and !greater_equal and !equal and !less and !less_equal) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = a64_state.VectorValue{
            .low = compareZeroVectorLanes(source.low, lane, greater or greater_equal, equal, greater_equal or less_equal),
            .high = if (full) compareZeroVectorLanes(source.high, lane, greater or greater_equal, equal, greater_equal or less_equal) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarVectorCompareZero(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff3ffc00;
        const greater = masked == 0x5e208800;
        const equal = masked == 0x5e209800;
        const less = masked == 0x5e20a800;
        const greater_equal = masked == 0x7e208800;
        const less_equal = masked == 0x7e209800;
        if (!greater and !equal and !less and !greater_equal and !less_equal) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size != 3) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const signed = @bitCast(i64, source);
        const result = if ((greater and signed > 0) or (equal and source == 0) or (less and signed < 0) or (greater_equal and signed >= 0) or (less_equal and signed <= 0)) ~@as(u64, 0) else 0;
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorNegate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf3ffc00) != 0x2e20b800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = a64_state.VectorValue{
            .low = subtractVectorLanes(0, source.low, lane),
            .high = if (full) subtractVectorLanes(0, source.high, lane) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarVectorNegate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xff3ffc00) != 0x7e20b800) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size != 3) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5)).low;
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = 0 -% source, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorAbsolute(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf3ffc00) != 0x0e20b800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = a64_state.VectorValue{
            .low = absoluteVectorLanes(source.low, lane),
            .high = if (full) absoluteVectorLanes(source.high, lane) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarVectorAbsolute(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xff3ffc00) != 0x5e20b800) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size != 3) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const result = if (@bitCast(i64, source) < 0) 0 -% source else source;
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }
};
