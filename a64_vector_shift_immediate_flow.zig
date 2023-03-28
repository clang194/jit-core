const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const float_estimate = @import("float_estimate.zig");
const float_fixed = @import("float_fixed.zig");
const float_fused = @import("float_fused.zig");
const float_refine = @import("float_refine.zig");
const float_rounding = @import("float_rounding.zig");
const float_status = @import("float_status.zig");
const main = @import("a64_core.zig");
const Core64 = main.Core64;
const Core64Error = main.Core64Error;
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
usingnamespace @import("a64_vector_dot.zig");
usingnamespace @import("a64_count_bits.zig");
usingnamespace @import("a64_memory_bits.zig");

pub const Core64Methods = struct {
    pub fn runVectorShiftImmediate(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf80fc00;
        if (masked != 0x0f000400 and masked != 0x0f001400 and masked != 0x0f002400 and masked != 0x0f003400 and masked != 0x0f005400 and masked != 0x0f007400 and masked != 0x0f008400 and masked != 0x0f008c00 and masked != 0x0f009400 and masked != 0x0f009c00 and masked != 0x0f00a400 and masked != 0x0f00e400 and masked != 0x0f00fc00 and masked != 0x2f000400 and masked != 0x2f001400 and masked != 0x2f002400 and masked != 0x2f003400 and masked != 0x2f004400 and masked != 0x2f005400 and masked != 0x2f007400 and masked != 0x2f009400 and masked != 0x2f009c00 and masked != 0x2f00a400 and masked != 0x2f00e400 and masked != 0x2f00fc00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const immh = @intCast(u4, (word >> 19) & 0xf);
        if (immh == 0) {
            return error.UnallocatedEncoding;
        }
        const fixed_to_float = masked == 0x0f00e400 or masked == 0x2f00e400;
        const float_to_fixed = masked == 0x0f00fc00 or masked == 0x2f00fc00;
        if (fixed_to_float or float_to_fixed) {
            if ((immh & 0xc) == 0) {
                return error.ReservedInstruction;
            }
            if ((immh & 8) != 0 and !full) {
                return error.ReservedInstruction;
            }

            const double = (immh & 8) != 0;
            const immediate = @as(u8, immh) << 3 | @intCast(u8, (word >> 16) & 7);
            const fractional_bits = (if (double) @as(usize, 128) else @as(usize, 64)) - @as(usize, immediate);
            const source = self.state.readVector(vectorRegFromWord(word >> 5));
            const result = if (fixed_to_float) blk: {
                break :blk if (masked == 0x0f00e400)
                    if (double) signedDoublewordsToFloatVector(source, fractional_bits) else signedWordsToFloatVector(full, source, fractional_bits)
                else if (double) unsignedDoublewordsToFloatVector(self.state.floatControl(), source, fractional_bits) else unsignedWordsToFloatVector(full, source, fractional_bits);
            } else blk: {
                const control = self.state.floatControl();
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                const converted = fixedFloatVector(control, &status, double, full, fractional_bits, masked == 0x2f00fc00, .zero, source) catch return error.MissingFallback;
                self.state.writeFloatStatus(status.raw());
                break :blk converted;
            };
            self.state.writeVector(vectorRegFromWord(word), result);
            self.state.pc +%= 4;
            return true;
        }
        if (masked == 0x0f008400 or masked == 0x0f008c00 or masked == 0x0f009400 or masked == 0x0f009c00 or masked == 0x2f008400 or masked == 0x2f008c00 or masked == 0x2f009400 or masked == 0x2f009c00) {
            if ((immh & 8) != 0) {
                return error.ReservedInstruction;
            }

            const target_lane = @as(u8, 8) << @intCast(u3, highestSetBit(immh));
            const source_lane = target_lane * 2;
            const immediate = @intCast(u8, (word >> 16) & 0x7f);
            const amount = source_lane - immediate;
            const target_bytes = @intCast(usize, target_lane / 8);
            const source = self.state.readVector(vectorRegFromWord(word >> 5));
            var saturated = false;
            const narrowed = if (masked == 0x2f008400 or masked == 0x2f008c00) blk: {
                const saturated_result = signedSaturatingNarrowUnsignedVectorLanes(source, target_bytes, amount, masked == 0x2f008c00);
                saturated = saturated_result.saturated;
                break :blk saturated_result.value;
            } else if (masked == 0x2f009400 or masked == 0x2f009c00) blk: {
                const saturated_result = unsignedSaturatingNarrowVectorLanes(source, target_bytes, amount, masked == 0x2f009c00);
                saturated = saturated_result.saturated;
                break :blk saturated_result.value;
            } else if (masked == 0x0f009400 or masked == 0x0f009c00) blk: {
                const saturated_result = signedSaturatingNarrowSignedVectorLanes(source, target_bytes, amount, masked == 0x0f009c00);
                saturated = saturated_result.saturated;
                break :blk saturated_result.value;
            } else if (masked == 0x0f008400)
                narrowShiftRightVectorLanes(source, target_bytes, amount)
            else
                narrowRoundedShiftRightVectorLanes(source, target_bytes, amount);
            if (saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            const result = if (full) blk: {
                var target = self.state.readVector(vectorRegFromWord(word));
                target.high = narrowed;
                break :blk target;
            } else a64_state.VectorValue{ .low = narrowed, .high = 0 };
            self.state.writeVector(vectorRegFromWord(word), result);
            self.state.pc +%= 4;
            return true;
        }
        if (masked == 0x0f00a400 or masked == 0x2f00a400) {
            if ((immh & 8) != 0) {
                return error.ReservedInstruction;
            }

            const lane = @as(u8, 8) << @intCast(u3, highestSetBit(immh));
            const immediate = @intCast(u8, (word >> 16) & 0x7f);
            const amount = @intCast(u6, immediate - @intCast(u8, lane));
            const source = self.state.readVector(vectorRegFromWord(word >> 5));
            const half = if (full) source.high else source.low;
            const result = if (masked == 0x0f00a400)
                widenSignedShiftLeftVectorHalf(half, lane, amount)
            else
                widenShiftLeftVectorHalf(half, lane, amount);
            self.state.writeVector(vectorRegFromWord(word), result);
            self.state.pc +%= 4;
            return true;
        }
        if ((immh & 8) != 0 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, highestSetBit(immh));
        const immediate = @intCast(u8, (word >> 16) & 0x7f);
        const signed_right = masked == 0x0f000400 or masked == 0x0f001400;
        const rounded_signed_right = masked == 0x0f002400 or masked == 0x0f003400;
        const rounded_right = masked == 0x2f002400 or masked == 0x2f003400;
        const insert_right = masked == 0x2f004400;
        const signed_saturating_left = masked == 0x0f007400;
        const unsigned_saturating_left = masked == 0x2f007400;
        const right = signed_right or rounded_signed_right or rounded_right or insert_right or masked == 0x2f000400 or masked == 0x2f001400;
        const amount = if (right)
            @intCast(u8, @as(u16, lane) * 2 - immediate)
        else
            immediate - @intCast(u8, lane);
        const input = self.state.readVector(vectorRegFromWord(word >> 5));
        if (signed_saturating_left) {
            const shifts = repeatedShiftAmountVector(lane, amount);
            const low = variableSignedSaturatingShiftLeftVectorLanes(input.low, shifts, lane);
            const high = if (full) variableSignedSaturatingShiftLeftVectorLanes(input.high, shifts, lane) else SaturatingShiftResult{ .value = 0, .saturated = false };
            if (low.saturated or high.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = low.value, .high = high.value });
            self.state.pc +%= 4;
            return true;
        }
        if (unsigned_saturating_left) {
            const shifts = repeatedShiftAmountVector(lane, amount);
            const low = variableUnsignedSaturatingShiftLeftVectorLanes(input.low, shifts, lane);
            const high = if (full) variableUnsignedSaturatingShiftLeftVectorLanes(input.high, shifts, lane) else SaturatingShiftResult{ .value = 0, .saturated = false };
            if (low.saturated or high.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = low.value, .high = high.value });
            self.state.pc +%= 4;
            return true;
        }
        if (insert_right or masked == 0x2f005400) {
            const target = self.state.readVector(vectorRegFromWord(word));
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{
                .low = if (insert_right) insertShiftRightVectorLanes(target.low, input.low, lane, amount) else insertShiftLeftVectorLanes(target.low, input.low, lane, amount),
                .high = if (full) if (insert_right) insertShiftRightVectorLanes(target.high, input.high, lane, amount) else insertShiftLeftVectorLanes(target.high, input.high, lane, amount) else 0,
            });
            self.state.pc +%= 4;
            return true;
        }
        const shifted = a64_state.VectorValue{
            .low = if (signed_right) shiftRightSignedVectorLanes(input.low, lane, amount) else if (rounded_signed_right) roundedShiftRightSignedVectorLanes(input.low, lane, amount) else if (rounded_right) roundedShiftRightVectorLanes(input.low, lane, amount) else if (right) shiftRightVectorLanes(input.low, lane, amount) else shiftLeftVectorLanes(input.low, lane, amount),
            .high = if (full) if (signed_right) shiftRightSignedVectorLanes(input.high, lane, amount) else if (rounded_signed_right) roundedShiftRightSignedVectorLanes(input.high, lane, amount) else if (rounded_right) roundedShiftRightVectorLanes(input.high, lane, amount) else if (right) shiftRightVectorLanes(input.high, lane, amount) else shiftLeftVectorLanes(input.high, lane, amount) else 0,
        };
        const result = if (masked == 0x0f001400 or masked == 0x0f003400 or masked == 0x2f001400 or masked == 0x2f003400) blk: {
            const target = self.state.readVector(vectorRegFromWord(word));
            break :blk a64_state.VectorValue{
                .low = addVectorLanes(target.low, shifted.low, lane),
                .high = if (full) addVectorLanes(target.high, shifted.high, lane) else 0,
            };
        } else shifted;
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarShiftImmediate(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff80fc00;
        const signed_narrow = masked == 0x5f009400;
        const signed_unsigned_narrow = masked == 0x7f008400;
        const unsigned_narrow = masked == 0x7f009400;
        const saturating_narrow = signed_narrow or signed_unsigned_narrow or unsigned_narrow;
        if (!saturating_narrow and masked != 0x5f000400 and masked != 0x5f001400 and masked != 0x5f002400 and masked != 0x5f003400 and masked != 0x5f005400 and masked != 0x7f000400 and masked != 0x7f001400 and masked != 0x7f002400 and masked != 0x7f003400 and masked != 0x7f004400 and masked != 0x7f005400) {
            return false;
        }

        const immh = @intCast(u4, (word >> 19) & 0xf);
        if (saturating_narrow) {
            if (immh == 0 or (immh & 8) != 0) {
                return error.UnallocatedEncoding;
            }

            const target_lane = @as(u8, 8) << @intCast(u3, highestSetBit(immh));
            const source_lane = target_lane * 2;
            const immediate = @intCast(u8, (word >> 16) & 0x7f);
            const amount = source_lane - immediate;
            const target_bytes = @intCast(usize, target_lane / 8);
            const source = a64_state.VectorValue{ .low = self.state.readVector(vectorRegFromWord(word >> 5)).low, .high = 0 };
            var saturated = false;
            const narrowed = if (signed_unsigned_narrow) blk: {
                const narrowed_result = signedSaturatingNarrowUnsignedVectorLanes(source, target_bytes, amount, false);
                saturated = narrowed_result.saturated;
                break :blk narrowed_result.value;
            } else if (unsigned_narrow) blk: {
                const narrowed_result = unsignedSaturatingNarrowVectorLanes(source, target_bytes, amount, false);
                saturated = narrowed_result.saturated;
                break :blk narrowed_result.value;
            } else blk: {
                const narrowed_result = signedSaturatingNarrowSignedVectorLanes(source, target_bytes, amount, false);
                saturated = narrowed_result.saturated;
                break :blk narrowed_result.value;
            };
            if (saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = narrowed, .high = 0 });
            self.state.pc +%= 4;
            return true;
        }

        if ((immh & 8) == 0) {
            return error.ReservedInstruction;
        }

        const immediate = @intCast(u8, (word >> 16) & 0x7f);
        const source = self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const result = if (masked == 0x5f005400)
            source << @intCast(u6, immediate - 64)
        else if (masked == 0x7f005400) blk: {
            const amount = immediate - 64;
            const shifted = source << @intCast(u6, amount);
            const target = self.state.readVector(vectorRegFromWord(word)).low;
            const mask = ~@as(u64, 0) << @intCast(u6, amount);
            break :blk (target & ~mask) | shifted;
        } else if (masked == 0x5f000400) blk: {
            const amount = 128 - @as(u8, immediate);
            const shifted = if (amount == 64)
                if ((source & 0x8000000000000000) == 0) @as(u64, 0) else ~@as(u64, 0)
            else
                @bitCast(u64, @bitCast(i64, source) >> @intCast(u6, amount));
            break :blk shifted;
        } else if (masked == 0x5f001400 or masked == 0x5f002400 or masked == 0x5f003400) blk: {
            const amount = 128 - @as(u8, immediate);
            const shifted = if (amount == 64)
                if ((source & 0x8000000000000000) == 0) @as(u64, 0) else ~@as(u64, 0)
            else
                @bitCast(u64, @bitCast(i64, source) >> @intCast(u6, amount));
            const target = self.state.readVector(vectorRegFromWord(word)).low;
            const rounded = (source >> @intCast(u6, amount - 1)) & 1;
            const extra = if (masked == 0x5f001400) target else if (masked == 0x5f002400) rounded else target +% rounded;
            break :blk shifted +% extra;
        } else blk: {
            const amount = 128 - @as(u8, immediate);
            const shifted = if (amount == 64) @as(u64, 0) else source >> @intCast(u6, amount);
            const target = self.state.readVector(vectorRegFromWord(word)).low;
            if (masked == 0x7f001400) {
                break :blk shifted +% target;
            }
            if (masked == 0x7f002400 or masked == 0x7f003400) {
                const rounded = (source >> @intCast(u6, amount - 1)) & 1;
                break :blk shifted +% if (masked == 0x7f002400) rounded else target +% rounded;
            }
            if (masked == 0x7f004400) {
                const mask = if (amount == 64) @as(u64, 0) else ~@as(u64, 0) >> @intCast(u6, amount);
                break :blk (target & ~mask) | shifted;
            }
            break :blk shifted;
        };
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }
};
