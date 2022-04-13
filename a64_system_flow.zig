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
    pub fn runVectorAnd(self: *Core64, word: u32) bool {
        const masked = word & 0xbfe0fc00;
        if (masked != 0x0e201c00 and masked != 0x0e601c00 and masked != 0x0ea01c00 and masked != 0x0ee01c00 and masked != 0x2e201c00 and masked != 0x2e601c00 and masked != 0x2ea01c00 and masked != 0x2ee01c00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const prior = self.state.readVector(vectorRegFromWord(word));
        const low = switch (masked) {
            0x0e201c00 => left.low & right.low,
            0x0e601c00 => left.low & ~right.low,
            0x0ea01c00 => left.low | right.low,
            0x0ee01c00 => left.low | ~right.low,
            0x2e201c00 => left.low ^ right.low,
            0x2e601c00 => right.low ^ ((right.low ^ left.low) & prior.low),
            0x2ea01c00 => prior.low ^ ((prior.low ^ left.low) & right.low),
            else => prior.low ^ ((prior.low ^ left.low) & ~right.low),
        };
        const high = switch (masked) {
            0x0e201c00 => left.high & right.high,
            0x0e601c00 => left.high & ~right.high,
            0x0ea01c00 => left.high | right.high,
            0x0ee01c00 => left.high | ~right.high,
            0x2e201c00 => left.high ^ right.high,
            0x2e601c00 => right.high ^ ((right.high ^ left.high) & prior.high),
            0x2ea01c00 => prior.high ^ ((prior.high ^ left.high) & right.high),
            else => prior.high ^ ((prior.high ^ left.high) & ~right.high),
        };
        const result = a64_state.VectorValue{
            .low = low,
            .high = if (full) high else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorNot(self: *Core64, word: u32) bool {
        if ((word & 0xbffffc00) != 0x2e205800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{
            .low = ~source.low,
            .high = if (full) ~source.high else 0,
        });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorThreeInputBitwise(self: *Core64, word: u32) bool {
        const masked = word & 0xffe08000;
        if (masked != 0xce000000 and masked != 0xce200000 and masked != 0xce400000) {
            return false;
        }

        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const third = self.state.readVector(vectorRegFromWord(word >> 10));
        const result = if (masked == 0xce000000) a64_state.VectorValue{
            .low = left.low ^ right.low ^ third.low,
            .high = left.high ^ right.high ^ third.high,
        } else if (masked == 0xce400000) sm3SelectWord(third, right, left) else a64_state.VectorValue{
            .low = left.low ^ (right.low & ~third.low),
            .high = left.high ^ (right.high & ~third.high),
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorThreeInputHash(self: *Core64, word: u32) bool {
        if ((word & 0xffe0c000) != 0xce408000) {
            return false;
        }

        const target = self.state.readVector(vectorRegFromWord(word));
        const message = self.state.readVector(vectorRegFromWord(word >> 16));
        const state = self.state.readVector(vectorRegFromWord(word >> 5));
        const mode = @intCast(u2, (word >> 10) & 3);
        const index = @intCast(usize, (word >> 12) & 3);
        const result = switch (mode) {
            0 => sm3MixOneA(target, message, state, index),
            1 => sm3MixOneB(target, message, state, index),
            2 => sm3MixTwoA(target, message, state, index),
            else => sm3MixTwoB(target, message, state, index),
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorRotatedXor(self: *Core64, word: u32) bool {
        if ((word & 0xffe0fc00) != 0xce608c00) {
            return false;
        }

        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        self.state.writeVector(vectorRegFromWord(word), xorRotatedDoublewordVector(left, right));
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorWideSchedule(self: *Core64, word: u32) bool {
        const first = (word & 0xfffffc00) == 0xcec08000;
        const next = (word & 0xffe0fc00) == 0xce608800;
        if (!first and !next) {
            return false;
        }

        const target = self.state.readVector(vectorRegFromWord(word));
        const state = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = if (next) blk: {
            const message = self.state.readVector(vectorRegFromWord(word >> 16));
            break :blk sha512ScheduleNext(target, message, state);
        } else sha512ScheduleFirst(target, state);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorMessageSchedule(self: *Core64, word: u32) bool {
        if ((word & 0xffe0f800) != 0xce60c000) {
            return false;
        }

        const target = self.state.readVector(vectorRegFromWord(word));
        const message = self.state.readVector(vectorRegFromWord(word >> 16));
        const state = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = if ((word & 0x400) == 0)
            sm3PrepareWordsFirst(target, message, state)
        else
            sm3PrepareWordsSecond(target, message, state);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorShaSchedule(self: *Core64, word: u32) bool {
        const three_input = (word & 0xffe0fc00) == 0x5e000c00;
        const schedule_three = (word & 0xffe0fc00) == 0x5e006000;
        const schedule_next = (word & 0xfffffc00) == 0x5e281800;
        const schedule_first = (word & 0xfffffc00) == 0x5e282800;
        const round_choose = (word & 0xffe0fc00) == 0x5e000000;
        const round_parity = (word & 0xffe0fc00) == 0x5e001000;
        const round_majority = (word & 0xffe0fc00) == 0x5e002000;
        const round_first = (word & 0xffe0fc00) == 0x5e004000;
        const round_second = (word & 0xffe0fc00) == 0x5e005000;
        if (!three_input and !schedule_three and !schedule_next and !schedule_first and !round_choose and !round_parity and !round_majority and !round_first and !round_second) {
            return false;
        }

        const target = self.state.readVector(vectorRegFromWord(word));
        const state = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = if (three_input) blk: {
            const message = self.state.readVector(vectorRegFromWord(word >> 16));
            break :blk sha1ScheduleFirst(target, message, state);
        } else if (schedule_three) blk: {
            const message = self.state.readVector(vectorRegFromWord(word >> 16));
            break :blk sha256ScheduleNext(target, message, state);
        } else if (round_choose) blk: {
            const message = self.state.readVector(vectorRegFromWord(word >> 16));
            break :blk sha1RoundChoose(target, message, state);
        } else if (round_parity) blk: {
            const message = self.state.readVector(vectorRegFromWord(word >> 16));
            break :blk sha1RoundParity(target, message, state);
        } else if (round_majority) blk: {
            const message = self.state.readVector(vectorRegFromWord(word >> 16));
            break :blk sha1RoundMajority(target, message, state);
        } else if (round_first) blk: {
            const message = self.state.readVector(vectorRegFromWord(word >> 16));
            break :blk sha256RoundFirst(target, message, state);
        } else if (round_second) blk: {
            const message = self.state.readVector(vectorRegFromWord(word >> 16));
            break :blk sha256RoundSecond(target, message, state);
        } else if (schedule_first)
            sha256ScheduleFirst(target, state)
        else
            sha1ScheduleNext(target, state);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runDivide(self: *Core64, word: u32) bool {
        const masked = word & 0x7fe0fc00;
        if (masked != 0x1ac00800 and masked != 0x1ac00c00) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const left = self.readSized(wide, regFromWord(word >> 5), false);
        const right = self.readSized(wide, regFromWord(word >> 16), false);
        const signed = masked == 0x1ac00c00;
        const result = if (signed)
            signedDivideSized(wide, left, right)
        else
            unsignedDivideSized(wide, left, right);
        self.writeSized(wide, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runCrc(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0x7fe0f000;
        if (masked != 0x1ac04000 and masked != 0x1ac05000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const size = @intCast(u2, (word >> 10) & 3);
        if (wide != (size == 3)) {
            return error.UnallocatedEncoding;
        }

        const accumulator = @intCast(u32, self.readSized(false, regFromWord(word >> 5), false));
        const value = self.readSized(wide, regFromWord(word >> 16), false);
        const result = if (masked == 0x1ac04000)
            crc32(accumulator, value, @as(u4, 1) << size)
        else
            crc32c(accumulator, value, @as(u4, 1) << size);
        self.writeSized(false, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVariableShift(self: *Core64, word: u32) bool {
        if ((word & 0x7fe0f000) != 0x1ac02000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const value = self.readSized(wide, regFromWord(word >> 5), false);
        const amount = @intCast(u6, self.readSized(wide, regFromWord(word >> 16), false) & if (wide) @as(u64, 63) else @as(u64, 31));
        const result = switch (@intCast(u2, (word >> 10) & 3)) {
            0 => if (wide) value << amount else @as(u64, @intCast(u32, value) << @intCast(u5, amount)),
            1 => if (wide) value >> amount else @as(u64, @intCast(u32, value) >> @intCast(u5, amount)),
            2 => if (wide) @bitCast(u64, @bitCast(i64, value) >> amount) else @as(u64, @bitCast(u32, @bitCast(i32, @intCast(u32, value)) >> @intCast(u5, amount))),
            else => rotateRightSized(wide, value, amount),
        };
        self.writeSized(wide, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runSystemHint(self: *Core64, word: u32) bool {
        if ((word & 0xfffff01f) != 0xd503201f) {
            return false;
        }
        const kind = switch ((word >> 5) & 0x7f) {
            1 => FaultKind64.yield_hint,
            2 => FaultKind64.wait_for_event,
            3 => FaultKind64.wait_for_interrupt,
            4 => FaultKind64.send_event,
            5 => FaultKind64.send_event_local,
            else => blk: {
                self.state.pc +%= 4;
                return true;
            },
        };
        self.state.pc +%= 4;
        if (self.hooks.exception) |callback| {
            callback(self.state.pc, kind, self.hooks.context);
        }
        return true;
    }

    pub fn runBarrier(self: *Core64, word: u32) bool {
        const masked = word & 0xfffff0ff;
        if (masked != 0xd503309f and masked != 0xd50330bf) {
            return false;
        }
        self.state.pc +%= 4;
        return true;
    }

    pub fn runClearExclusive(self: *Core64, word: u32) bool {
        if ((word & 0xfffff0ff) != 0xd503305f) {
            return false;
        }
        self.state.exclusive = false;
        self.state.pc +%= 4;
        return true;
    }

    pub fn runSystemRegisterWrite(self: *Core64, word: u32) bool {
        const masked = word & 0xffffffe0;
        const value = @intCast(u32, self.readSized(false, regFromWord(word), false));
        switch (masked) {
            0xd51b4400 => self.state.writeFloatControl(value),
            0xd51b4420 => self.state.writeFloatStatus(value),
            0xd51bd040 => if (self.hooks.thread_value) |cell| cell.* = self.readSized(true, regFromWord(word), false),
            else => return false,
        }
        self.state.pc +%= 4;
        return true;
    }

    pub fn runSystemRegisterRead(self: *Core64, word: u32) bool {
        const masked = word & 0xffffffe0;
        const value = switch (masked) {
            0xd53b0020 => @as(u64, self.hooks.cache_type_value),
            0xd53b00e0 => @as(u64, self.hooks.zero_cache_block_words_log2),
            0xd53b4400 => @as(u64, self.state.floatControl().raw()),
            0xd53b4420 => @as(u64, self.state.floatStatus()),
            0xd53bd040 => if (self.hooks.thread_value) |cell| cell.* else @as(u64, 0),
            0xd53bd060 => if (self.hooks.read_only_thread_value) |cell| cell.* else @as(u64, 0),
            0xd53be020 => if (self.hooks.counter_value) |callback| callback(self.hooks.context) else @as(u64, 0),
            else => return false,
        };
        self.writeSized(masked == 0xd53bd040 or masked == 0xd53bd060 or masked == 0xd53be020, regFromWord(word), value, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runCacheMaintenance(self: *Core64, word: u32) Core64Error!bool {
        const action = switch (word & 0xffffffe0) {
            0xd5087620 => CacheAction64.invalidate_address,
            0xd5087640 => CacheAction64.invalidate_set_way,
            0xd5087a40 => CacheAction64.clean_set_way,
            0xd5087e40 => CacheAction64.clean_invalidate_set_way,
            0xd50b7420 => CacheAction64.zero_address,
            0xd50b7a20 => CacheAction64.clean_address_inner,
            0xd50b7b20 => CacheAction64.clean_address_unified,
            0xd50b7c20 => CacheAction64.clean_address_persistent,
            0xd50b7e20 => CacheAction64.clean_invalidate_address,
            else => return false,
        };
        const address = self.readSized(true, regFromWord(word), false);
        if (self.hooks.cache) |callback| {
            callback(action, address, self.hooks.context);
        } else if (action == .zero_address) {
            var current = address;
            var remaining = @intCast(usize, @as(u64, 4) << @intCast(u6, self.hooks.zero_cache_block_words_log2));
            while (remaining >= 16) {
                try self.writeMemoryVector(current, a64_state.VectorValue{ .low = 0, .high = 0 });
                current +%= 16;
                remaining -= 16;
            }
            while (remaining >= 8) {
                try self.writeMemory(current, 8, 0);
                current +%= 8;
                remaining -= 8;
            }
            while (remaining >= 4) {
                try self.writeMemory(current, 4, 0);
                current +%= 4;
                remaining -= 4;
            }
        }
        self.state.pc +%= 4;
        return true;
    }

    pub fn runLeadingZeroCount(self: *Core64, word: u32) bool {
        const masked = word & 0x7ffffc00;
        if (masked != 0x5ac01000 and masked != 0x5ac01400) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const value = self.readSized(wide, regFromWord(word >> 5), false);
        const sign = masked == 0x5ac01400;
        const result = if (sign)
            if (wide) countLeadingSignBits64(value) else @as(u64, countLeadingSignBits32(@intCast(u32, value)))
        else if (wide) countLeadingZeroes64(value) else @as(u64, countLeadingZeroes32(@intCast(u32, value)));
        self.writeSized(wide, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runMultiplyAdd(self: *Core64, word: u32) bool {
        if ((word & 0x7fe00000) != 0x1b000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const left = self.readSized(wide, regFromWord(word >> 5), false);
        const right = self.readSized(wide, regFromWord(word >> 16), false);
        const addend = self.readSized(wide, regFromWord(word >> 10), false);
        const product = if (wide) left *% right else @as(u64, @intCast(u32, @intCast(u32, left) *% @intCast(u32, right)));
        const result = if ((word & 0x00008000) == 0) addend +% product else addend -% product;
        self.writeSized(wide, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runMultiplyHigh(self: *Core64, word: u32) bool {
        const masked = word & 0xffe0fc00;
        if (masked != 0x9b407c00 and masked != 0x9bc07c00) {
            return false;
        }

        const left = self.readSized(true, regFromWord(word >> 5), false);
        const right = self.readSized(true, regFromWord(word >> 16), false);
        const result = if (masked == 0x9bc07c00)
            @intCast(u64, (@as(u128, left) * @as(u128, right)) >> 64)
        else
            @bitCast(u64, @intCast(i64, (@as(i128, @bitCast(i64, left)) * @as(i128, @bitCast(i64, right))) >> 64));
        self.writeSized(true, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runLongMultiplyAdd(self: *Core64, word: u32) bool {
        if ((word & 0xff600000) != 0x9b200000) {
            return false;
        }

        const left = @intCast(u32, self.readSized(false, regFromWord(word >> 5), false));
        const right = @intCast(u32, self.readSized(false, regFromWord(word >> 16), false));
        const product = if ((word & 0x00800000) == 0)
            @bitCast(u64, @as(i64, @bitCast(i32, left)) *% @as(i64, @bitCast(i32, right)))
        else
            @as(u64, left) *% @as(u64, right);
        const addend = self.readSized(true, regFromWord(word >> 10), false);
        const result = if ((word & 0x00008000) == 0) addend +% product else addend -% product;
        self.writeSized(true, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }
};
