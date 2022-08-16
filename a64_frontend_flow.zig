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
    pub fn runPcRelative(self: *Core64, word: u32) bool {
        if ((word & 0x1f000000) != 0x10000000) {
            return false;
        }

        const page = (word & 0x80000000) != 0;
        const immlo = (word >> 29) & 3;
        const immhi = (word >> 5) & 0x7ffff;
        const raw = (@as(u64, immhi) << 2) | @as(u64, immlo);
        const signed = bits.signExtend64(raw, 21);
        var immediate = @bitCast(u64, signed);
        var base = self.state.pc;
        if (page) {
            immediate = @bitCast(u64, signed << 12);
            base &= ~@as(u64, 0xfff);
        }
        self.writeSized(true, regFromWord(word), base +% immediate, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runBranch(self: *Core64, word: u32) bool {
        if ((word & 0xff000010) == 0x54000000) {
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 5) & 0x7ffff) << 2, 21));
            if (self.conditionHolds(@intCast(u4, word & 0xf))) {
                self.state.pc +%= offset;
            } else {
                self.state.pc +%= 4;
            }
            return true;
        }

        if ((word & 0x7c000000) == 0x14000000) {
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, word & 0x03ffffff) << 2, 28));
            if ((word & 0x80000000) != 0) {
                self.state.write(.x30, self.state.pc +% 4);
            }
            self.state.pc +%= offset;
            return true;
        }

        if ((word & 0xfffffc1f) == 0xd61f0000) {
            self.state.pc = self.state.read(regFromWord(word >> 5));
            return true;
        }

        if ((word & 0xfffffc1f) == 0xd63f0000) {
            const target = self.state.read(regFromWord(word >> 5));
            self.state.write(.x30, self.state.pc +% 4);
            self.state.pc = target;
            return true;
        }

        if ((word & 0xfffffc1f) == 0xd65f0000) {
            self.state.pc = self.state.read(regFromWord(word >> 5));
            return true;
        }

        return false;
    }

    pub fn runCompareBranch(self: *Core64, word: u32) bool {
        if ((word & 0x7e000000) == 0x34000000) {
            const wide = (word & 0x80000000) != 0;
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 5) & 0x7ffff) << 2, 21));
            const value = self.readSized(wide, regFromWord(word), false);
            const want_nonzero = (word & 0x01000000) != 0;
            if ((value != 0) == want_nonzero) {
                self.state.pc +%= offset;
            } else {
                self.state.pc +%= 4;
            }
            return true;
        }

        if ((word & 0x7e000000) == 0x36000000) {
            const bit_index = @intCast(u6, ((word >> 26) & 0x20) | ((word >> 19) & 0x1f));
            const wide = bit_index >= 32;
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 5) & 0x3fff) << 2, 16));
            const value = self.readSized(wide, regFromWord(word), false);
            const bit_set = ((value >> bit_index) & 1) != 0;
            const want_set = (word & 0x01000000) != 0;
            if (bit_set == want_set) {
                self.state.pc +%= offset;
            } else {
                self.state.pc +%= 4;
            }
            return true;
        }

        return false;
    }

    pub fn runSupervisorCall(self: *Core64, word: u32) bool {
        if ((word & 0xffe0001f) != 0xd4000001) {
            return false;
        }
        const callback = self.hooks.supervisor orelse return false;
        self.state.pc +%= 4;
        callback((word >> 5) & 0xffff, &self.state, self.hooks.context);
        self.clearReservation();
        return true;
    }
};
