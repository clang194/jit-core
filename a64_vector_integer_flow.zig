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
    pub fn runScalarVectorArithmetic(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff20fc00;
        const saturating_add = masked == 0x5e200c00;
        const saturating_sub = masked == 0x5e202c00;
        const unsigned_saturating_add = masked == 0x7e200c00;
        const unsigned_saturating_sub = masked == 0x7e202c00;
        const saturating_multiply_high = masked == 0x5e20b400;
        if (!saturating_add and !saturating_sub and !unsigned_saturating_add and !unsigned_saturating_sub and !saturating_multiply_high and masked != 0x5e203400 and masked != 0x5e203c00 and masked != 0x5e204400 and masked != 0x5e205400 and masked != 0x5e208400 and masked != 0x5e208c00 and masked != 0x7e203400 and masked != 0x7e203c00 and masked != 0x7e204400 and masked != 0x7e205400 and masked != 0x7e208400 and masked != 0x7e208c00) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (saturating_multiply_high and (size == 0 or size == 3)) {
            return error.ReservedInstruction;
        }
        if (!saturating_add and !saturating_sub and !unsigned_saturating_add and !unsigned_saturating_sub and !saturating_multiply_high and size != 3) {
            return error.ReservedInstruction;
        }

        const left = self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const right = self.state.readVector(vectorRegFromWord(word >> 16)).low;
        if (saturating_add or saturating_sub or unsigned_saturating_add or unsigned_saturating_sub) {
            const width = @as(u8, 8) << @intCast(u3, size);
            const saturated = if (saturating_add)
                signedSaturatedAdd(width, left, right)
            else if (saturating_sub)
                signedSaturatedSub(width, left, right)
            else if (unsigned_saturating_add)
                unsignedSaturatedAdd(width, left, right)
            else
                unsignedSaturatedSub(width, left, right);
            if (saturated.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = saturated.value, .high = 0 });
            self.state.pc +%= 4;
            return true;
        }
        if (saturating_multiply_high) {
            const width = @as(u8, 8) << @intCast(u3, size);
            const saturated = signedSaturatedDoublingMultiplyHigh(width, left, right);
            if (saturated.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = saturated.value, .high = 0 });
            self.state.pc +%= 4;
            return true;
        }

        const result = if (masked == 0x5e208400)
            left +% right
        else if (masked == 0x7e208400)
            left -% right
        else if (masked == 0x5e203400 and @bitCast(i64, left) > @bitCast(i64, right))
            ~@as(u64, 0)
        else if (masked == 0x5e203c00 and (@bitCast(i64, left) > @bitCast(i64, right) or left == right))
            ~@as(u64, 0)
        else if (masked == 0x7e203400 and left > right)
            ~@as(u64, 0)
        else if (masked == 0x7e203c00 and left >= right)
            ~@as(u64, 0)
        else if (masked == 0x7e208c00 and left == right)
            ~@as(u64, 0)
        else if (masked == 0x5e208c00)
            sharedBitVectorLanes(left, right, 64)
        else if (masked == 0x5e204400)
            variableSignedShiftVectorLanes(left, right, 64)
        else if (masked == 0x5e205400)
            variableRoundedSignedShiftVectorLanes(left, right, 64)
        else if (masked == 0x7e204400)
            variableUnsignedShiftVectorLanes(left, right, 64)
        else if (masked == 0x7e205400)
            variableRoundedUnsignedShiftVectorLanes(left, right, 64)
        else
            0;
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarPairAdd(self: *Core64, word: u32) Core64Error!bool {
        const integer_pair = (word & 0xff20fc00) == 0x5e20bc00;
        const float_pair = (word & 0xffbffc00) == 0x7e30d800;
        const masked_float_pair = word & 0xffbffc00;
        const max_number = masked_float_pair == 0x7e30c800;
        const max_plain = masked_float_pair == 0x7e30f800;
        const min_number = masked_float_pair == 0x7eb0c800;
        const min_plain = masked_float_pair == 0x7eb0f800;
        const float_min_max = max_number or max_plain or min_number or min_plain;
        if (!integer_pair and !float_pair and !float_min_max) {
            return false;
        }

        if (float_pair or float_min_max) {
            const double = ((word >> 22) & 1) != 0;
            const bytes = if (double) @as(usize, 8) else @as(usize, 4);
            const source = self.state.readVector(vectorRegFromWord(word >> 5));
            const left = vectorElement(source, 0, bytes);
            const right = vectorElement(source, 1, bytes);
            const control = self.state.floatControl();
            const nan_mode = self.hooks.float_nan_mode;
            const result = if (float_pair)
                floatAdd(control, nan_mode, double, left, right)
            else if (max_number)
                floatMaxNumber(control, nan_mode, double, left, right)
            else if (max_plain)
                floatMax(control, nan_mode, double, left, right)
            else if (min_number)
                floatMinNumber(control, nan_mode, double, left, right)
            else
                floatMin(control, nan_mode, double, left, right);
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
            self.state.pc +%= 4;
            return true;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size != 3) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = source.low +% source.high, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorAdd(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed_saturating_add = masked == 0x0e200c00;
        const signed_saturating_sub = masked == 0x0e202c00;
        const unsigned_saturating_add = masked == 0x2e200c00;
        const unsigned_saturating_sub = masked == 0x2e202c00;
        const signed_saturating_multiply_high = masked == 0x0e20b400;
        const signed_rounding_saturating_multiply_high = masked == 0x2e20b400;
        if (!signed_saturating_add and !signed_saturating_sub and !unsigned_saturating_add and !unsigned_saturating_sub and !signed_saturating_multiply_high and !signed_rounding_saturating_multiply_high and masked != 0x0e200400 and masked != 0x0e201400 and masked != 0x0e202400 and masked != 0x0e208400 and masked != 0x0e209400 and masked != 0x0e209c00 and masked != 0x2e200400 and masked != 0x2e201400 and masked != 0x2e202400 and masked != 0x2e208400 and masked != 0x2e209400 and masked != 0x2e209c00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if ((signed_saturating_multiply_high or signed_rounding_saturating_multiply_high) and (size == 0 or size == 3)) {
            return error.ReservedInstruction;
        }
        if (masked == 0x2e209c00 and size != 0) {
            return error.ReservedInstruction;
        }
        if (size == 3 and (masked == 0x0e200400 or masked == 0x0e201400 or masked == 0x0e202400 or masked == 0x0e209400 or masked == 0x0e209c00 or masked == 0x2e200400 or masked == 0x2e201400 or masked == 0x2e202400 or masked == 0x2e209400 or !full)) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        if (signed_saturating_add or signed_saturating_sub or unsigned_saturating_add or unsigned_saturating_sub) {
            const low = saturatingVectorLanes(left.low, right.low, lane, signed_saturating_add or signed_saturating_sub, signed_saturating_add or unsigned_saturating_add);
            const high = if (full) saturatingVectorLanes(left.high, right.high, lane, signed_saturating_add or signed_saturating_sub, signed_saturating_add or unsigned_saturating_add) else SaturatingVectorResult{ .value = 0, .saturated = false };
            if (low.saturated or high.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = low.value, .high = high.value });
            self.state.pc +%= 4;
            return true;
        }
        if (signed_saturating_multiply_high) {
            const low = signedSaturatingDoublingMultiplyHighVectorLanes(left.low, right.low, lane);
            const high = if (full) signedSaturatingDoublingMultiplyHighVectorLanes(left.high, right.high, lane) else SaturatingVectorResult{ .value = 0, .saturated = false };
            if (low.saturated or high.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = low.value, .high = high.value });
            self.state.pc +%= 4;
            return true;
        }
        if (signed_rounding_saturating_multiply_high) {
            const parts = signedSaturatingDoublingProductPartsVector(left, right, full, lane);
            if (parts.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            const rounded = a64_state.VectorValue{
                .low = addVectorLanes(parts.high.low, shiftRightVectorLanes(parts.low.low, lane, lane - 1), lane),
                .high = if (full) addVectorLanes(parts.high.high, shiftRightVectorLanes(parts.low.high, lane, lane - 1), lane) else 0,
            };
            self.state.writeVector(vectorRegFromWord(word), rounded);
            self.state.pc +%= 4;
            return true;
        }
        const result = if (masked == 0x2e209c00)
            polynomialByteVector(full, left, right)
        else if (masked == 0x0e209400 or masked == 0x2e209400) blk: {
            const prior = self.state.readVector(vectorRegFromWord(word));
            break :blk a64_state.VectorValue{
                .low = if (masked == 0x0e209400) addVectorLanes(prior.low, multiplyVectorLanes(left.low, right.low, lane), lane) else subtractVectorLanes(prior.low, multiplyVectorLanes(left.low, right.low, lane), lane),
                .high = if (full) if (masked == 0x0e209400) addVectorLanes(prior.high, multiplyVectorLanes(left.high, right.high, lane), lane) else subtractVectorLanes(prior.high, multiplyVectorLanes(left.high, right.high, lane), lane) else 0,
            };
        } else a64_state.VectorValue{
            .low = if (masked == 0x0e200400) signedHalvingAddVectorLanes(left.low, right.low, lane) else if (masked == 0x0e201400) signedRoundingHalvingAddVectorLanes(left.low, right.low, lane) else if (masked == 0x0e202400) signedHalvingSubtractVectorLanes(left.low, right.low, lane) else if (masked == 0x2e200400) halvingAddVectorLanes(left.low, right.low, lane) else if (masked == 0x2e201400) roundingHalvingAddVectorLanes(left.low, right.low, lane) else if (masked == 0x2e202400) halvingSubtractVectorLanes(left.low, right.low, lane) else if (masked == 0x0e208400) addVectorLanes(left.low, right.low, lane) else if (masked == 0x0e209c00) multiplyVectorLanes(left.low, right.low, lane) else subtractVectorLanes(left.low, right.low, lane),
            .high = if (full) if (masked == 0x0e200400) signedHalvingAddVectorLanes(left.high, right.high, lane) else if (masked == 0x0e201400) signedRoundingHalvingAddVectorLanes(left.high, right.high, lane) else if (masked == 0x0e202400) signedHalvingSubtractVectorLanes(left.high, right.high, lane) else if (masked == 0x2e200400) halvingAddVectorLanes(left.high, right.high, lane) else if (masked == 0x2e201400) roundingHalvingAddVectorLanes(left.high, right.high, lane) else if (masked == 0x2e202400) halvingSubtractVectorLanes(left.high, right.high, lane) else if (masked == 0x0e208400) addVectorLanes(left.high, right.high, lane) else if (masked == 0x0e209c00) multiplyVectorLanes(left.high, right.high, lane) else subtractVectorLanes(left.high, right.high, lane) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorWideningArithmetic(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed_difference = masked == 0x0e205000 or masked == 0x0e207000;
        const signed_multiply_accumulate = masked == 0x0e208000;
        const signed_multiply_subtract = masked == 0x0e20a000;
        const signed_multiply_long = masked == 0x0e20c000;
        const signed_saturating_multiply_long = masked == 0x0e20d000;
        const unsigned_multiply_accumulate = masked == 0x2e208000;
        const unsigned_multiply_subtract = masked == 0x2e20a000;
        const unsigned_multiply_long = masked == 0x2e20c000;
        const polynomial_wide = masked == 0x0e20e000;
        const multiplying_long = signed_multiply_accumulate or signed_multiply_subtract or signed_multiply_long or signed_saturating_multiply_long or unsigned_multiply_accumulate or unsigned_multiply_subtract or unsigned_multiply_long;
        const signed = masked == 0x0e200000 or masked == 0x0e201000 or masked == 0x0e202000 or masked == 0x0e203000 or signed_difference or signed_multiply_accumulate or signed_multiply_subtract or signed_multiply_long or signed_saturating_multiply_long;
        const subtracting = masked == 0x0e202000 or masked == 0x0e203000 or masked == 0x2e202000 or masked == 0x2e203000;
        const widening_source_pair = masked == 0x0e200000 or masked == 0x0e202000 or masked == 0x2e200000 or masked == 0x2e202000;
        const accumulating_difference = masked == 0x0e205000 or masked == 0x2e205000;
        const absolute_difference = masked == 0x0e207000 or masked == 0x2e207000 or accumulating_difference;
        if (!signed and masked != 0x2e201000 and masked != 0x2e203000 and !widening_source_pair and !absolute_difference and !multiplying_long and !polynomial_wide) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (polynomial_wide and (size == 1 or size == 2)) {
            return error.ReservedInstruction;
        }
        if (!polynomial_wide and size == 3) {
            return error.ReservedInstruction;
        }
        if (signed_saturating_multiply_long and size == 0) {
            return error.ReservedInstruction;
        }

        const upper = (word & 0x40000000) != 0;
        const base = self.state.readVector(vectorRegFromWord(word >> 5));
        const addend = self.state.readVector(vectorRegFromWord(word >> 16));
        if (polynomial_wide) {
            const result = if (size == 3)
                polynomialWideWordProduct(if (upper) base.high else base.low, if (upper) addend.high else addend.low)
            else
                polynomialWideByteVector(upper, base, addend);
            self.state.writeVector(vectorRegFromWord(word), result);
            self.state.pc +%= 4;
            return true;
        }

        const source_bytes = @as(usize, 1) << size;
        const target_bytes = source_bytes * 2;
        const source_bits = @intCast(u8, source_bytes * 8);
        const source_mask = ones(source_bits);
        const addend_half = if (upper) addend.high else addend.low;
        const base_half = if (upper) base.high else base.low;
        if (signed_saturating_multiply_long) {
            const saturated = signedSaturatingDoublingLongProductHalf(base_half, addend_half, source_bits);
            if (saturated.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), saturated.value);
            self.state.pc +%= 4;
            return true;
        }
        var result = a64_state.VectorValue{ .low = 0, .high = 0 };
        var index: usize = 0;
        while (index < 8 / source_bytes) : (index += 1) {
            const shift = @intCast(u6, index * source_bytes * 8);
            const raw_left = (base_half >> shift) & source_mask;
            const left = if (widening_source_pair or absolute_difference or signed_multiply_accumulate or signed_multiply_subtract or signed_multiply_long or unsigned_multiply_accumulate or unsigned_multiply_subtract or unsigned_multiply_long) if (signed) signExtendRuntime(raw_left, @intCast(u6, source_bits)) else raw_left else vectorElement(base, index, target_bytes);
            const raw = (addend_half >> shift) & source_mask;
            const right = if (signed) signExtendRuntime(raw, @intCast(u6, source_bits)) else raw;
            const difference = if (signed_difference) blk: {
                const signed_left = @bitCast(i64, left);
                const signed_right = @bitCast(i64, right);
                break :blk @bitCast(u64, if (signed_left >= signed_right) signed_left - signed_right else signed_right - signed_left);
            } else if (left >= right) left - right else right - left;
            const product = if (signed) @bitCast(u64, @bitCast(i64, left) *% @bitCast(i64, right)) else left *% right;
            const value = if (signed_multiply_accumulate or unsigned_multiply_accumulate) vectorElement(self.state.readVector(vectorRegFromWord(word)), index, target_bytes) +% product else if (signed_multiply_subtract or unsigned_multiply_subtract) vectorElement(self.state.readVector(vectorRegFromWord(word)), index, target_bytes) -% product else if (signed_multiply_long or unsigned_multiply_long) product else if (accumulating_difference) vectorElement(self.state.readVector(vectorRegFromWord(word)), index, target_bytes) +% difference else if (absolute_difference) difference else if (subtracting) left -% right else left +% right;
            setVectorElement(&result, index, target_bytes, value);
        }
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorHighNarrowArithmetic(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const adding = masked == 0x0e204000;
        const subtracting = masked == 0x0e206000;
        const rounded_adding = masked == 0x2e204000;
        const rounded_subtracting = masked == 0x2e206000;
        if (!adding and !subtracting and !rounded_adding and !rounded_subtracting) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3) {
            return error.ReservedInstruction;
        }

        const upper = (word & 0x40000000) != 0;
        const target_bytes = @as(usize, 1) << size;
        const wide_bytes = target_bytes * 2;
        const target_bits = @intCast(u8, target_bytes * 8);
        const wide_mask = ones(target_bits * 2);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        var narrowed_value = a64_state.VectorValue{ .low = 0, .high = 0 };
        var index: usize = 0;
        while (index < 8 / target_bytes) : (index += 1) {
            const wide_left = vectorElement(left, index, wide_bytes);
            const wide_right = vectorElement(right, index, wide_bytes);
            var combined = (if (adding or rounded_adding) wide_left +% wide_right else wide_left -% wide_right) & wide_mask;
            if (rounded_adding or rounded_subtracting) {
                combined = (combined +% (@as(u64, 1) << @intCast(u6, target_bits - 1))) & wide_mask;
            }
            setVectorElement(&narrowed_value, index, target_bytes, combined >> @intCast(u6, target_bits));
        }

        const result = if (upper) a64_state.VectorValue{ .low = self.state.readVector(vectorRegFromWord(word)).low, .high = narrowed_value.low } else a64_state.VectorValue{ .low = narrowed_value.low, .high = 0 };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorDifference(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed_plain = masked == 0x0e207400;
        const plain = signed_plain or masked == 0x2e207400;
        const signed_accumulating = masked == 0x0e207c00;
        const accumulating = signed_accumulating or masked == 0x2e207c00;
        if (!plain and !accumulating) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3) {
            return error.ReservedInstruction;
        }

        const full = (word & 0x40000000) != 0;
        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const difference = a64_state.VectorValue{
            .low = if (signed_plain or signed_accumulating) differenceSignedVectorLanes(left.low, right.low, lane) else differenceUnsignedVectorLanes(left.low, right.low, lane),
            .high = if (full) if (signed_plain or signed_accumulating) differenceSignedVectorLanes(left.high, right.high, lane) else differenceUnsignedVectorLanes(left.high, right.high, lane) else 0,
        };
        const result = if (plain) difference else blk: {
            const prior = self.state.readVector(vectorRegFromWord(word));
            break :blk a64_state.VectorValue{
                .low = addVectorLanes(prior.low, difference.low, lane),
                .high = if (full) addVectorLanes(prior.high, difference.high, lane) else 0,
            };
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }
};
