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
    pub fn runVectorInterleave(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfe0fc00) != 0x0e003800) {
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
        self.state.writeVector(vectorRegFromWord(word), interleaveLowerVector(left, right, bytes, if (full) @as(usize, 16) else @as(usize, 8)));
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

    pub fn runVectorCompareZero(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf3ffc00;
        const greater = masked == 0x0e208800;
        const equal = masked == 0x0e209800;
        const less = masked == 0x0e20a800;
        if (!greater and !equal and !less) {
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
            .low = compareZeroVectorLanes(source.low, lane, greater, equal),
            .high = if (full) compareZeroVectorLanes(source.high, lane, greater, equal) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
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


};
