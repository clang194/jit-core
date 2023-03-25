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
    pub fn runPairLoadStore(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x3e000000) != 0x28000000) {
            return false;
        }

        const opcode = @intCast(u2, word >> 30);
        const not_postindex = ((word >> 24) & 1) != 0;
        const writeback = ((word >> 23) & 1) != 0;
        const load = ((word >> 22) & 1) != 0;
        if ((!load and (opcode & 1) != 0) or opcode == 3) {
            return error.UnallocatedEncoding;
        }

        const offset_first = not_postindex or !writeback;
        const signed_load = (opcode & 1) != 0;
        const bytes = if ((opcode & 2) != 0) @as(usize, 8) else @as(usize, 4);
        const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 15) & 0x7f), 7)) << @intCast(u6, if (bytes == 8) 3 else 2);
        const first = regFromWord(word);
        const base_reg = regFromWord(word >> 5);
        const second = regFromWord(word >> 10);

        if (load and first == second) {
            return error.Unpredictable;
        }
        if (writeback and base_reg != .sp and (base_reg == first or base_reg == second)) {
            return error.Unpredictable;
        }

        var address = self.readSized(true, base_reg, true);
        if (offset_first) {
            address +%= offset;
        }

        if (load) {
            const low = try self.readMemory(address, bytes);
            const high = try self.readMemory(address +% @intCast(u64, bytes), bytes);
            if (signed_load) {
                self.writeSized(true, first, @bitCast(u64, bits.signExtend64(low, 32)), false);
                self.writeSized(true, second, @bitCast(u64, bits.signExtend64(high, 32)), false);
            } else {
                self.writeSized(bytes == 8, first, low, false);
                self.writeSized(bytes == 8, second, high, false);
            }
        } else {
            try self.writeMemory(address, bytes, self.readSized(bytes == 8, first, false));
            try self.writeMemory(address +% @intCast(u64, bytes), bytes, self.readSized(bytes == 8, second, false));
        }

        if (writeback) {
            if (!offset_first) {
                address +%= offset;
            }
            self.writeSized(true, base_reg, address, true);
        }
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorPairLoadStore(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x3e000000) != 0x2c000000) {
            return false;
        }

        const opcode = @intCast(u2, word >> 30);
        const not_postindex = ((word >> 24) & 1) != 0;
        const writeback = ((word >> 23) & 1) != 0;
        const load = ((word >> 22) & 1) != 0;
        if (opcode == 3) {
            return error.UnallocatedEncoding;
        }

        const offset_first = not_postindex or !writeback;
        const bytes = @as(usize, 4) << opcode;
        const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 15) & 0x7f), 7)) << @intCast(u6, 2 + opcode);
        const first = vectorRegFromWord(word);
        const base_reg = regFromWord(word >> 5);
        const second = vectorRegFromWord(word >> 10);

        if (load and first == second) {
            return error.Unpredictable;
        }

        var address = self.readSized(true, base_reg, true);
        if (offset_first) {
            address +%= offset;
        }

        if (load) {
            const low = try self.readVectorPairMemory(address, bytes);
            const high = try self.readVectorPairMemory(address +% @intCast(u64, bytes), bytes);
            self.state.writeVector(first, low);
            self.state.writeVector(second, high);
        } else {
            try self.writeVectorPairMemory(address, bytes, self.state.readVector(first));
            try self.writeVectorPairMemory(address +% @intCast(u64, bytes), bytes, self.state.readVector(second));
        }

        if (writeback) {
            if (!offset_first) {
                address +%= offset;
            }
            self.writeSized(true, base_reg, address, true);
        }
        self.state.pc +%= 4;
        return true;
    }
};
