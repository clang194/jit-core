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
    pub fn runVectorMultiplyAddByElement(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf00f400;
        const multiply_only = masked == 0x0f008000;
        const saturating_multiply_high = masked == 0x0f00c000;
        const rounding_saturating_multiply_high = masked == 0x0f00d000;
        const accumulate = masked == 0x2f000000;
        const subtracting = masked == 0x2f004000;
        if (!multiply_only and !saturating_multiply_high and !rounding_saturating_multiply_high and !accumulate and !subtracting) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 0 or size == 3) {
            return error.ReservedInstruction;
        }

        const full = (word & 0x40000000) != 0;
        const bytes = @as(usize, 1) << size;
        const total = if (full) @as(usize, 16) else @as(usize, 8);
        const high = @intCast(usize, (word >> 11) & 1);
        const left_index = @intCast(usize, (word >> 21) & 1);
        const middle_index = @intCast(usize, (word >> 20) & 1);
        const lane_index = if (size == 1)
            (high << 2) | (left_index << 1) | middle_index
        else
            (high << 1) | left_index;
        const element_reg = if (size == 1)
            (word >> 16) & 0xf
        else
            ((word >> 16) & 0xf) | (((word >> 20) & 1) << 4);
        const element = vectorElement(self.state.readVector(vectorRegFromWord(element_reg)), lane_index, bytes);
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const prior = self.state.readVector(vectorRegFromWord(word));
        var result = a64_state.VectorValue{ .low = 0, .high = 0 };
        var saturated_any = false;
        var index: usize = 0;
        while (index < total / bytes) : (index += 1) {
            const left = vectorElement(source, index, bytes);
            const width = @intCast(u8, bytes * 8);
            const product = if (saturating_multiply_high)
                signedSaturatedDoublingMultiplyHigh(width, left, element)
            else if (rounding_saturating_multiply_high) blk: {
                const parts = signedSaturatingDoublingProductParts64(left, element, width);
                const value = (parts.high +% (parts.low >> @intCast(u6, width - 1))) & ones(width);
                break :blk SaturatingIntegerResult{ .value = value, .saturated = parts.saturated };
            } else SaturatingIntegerResult{ .value = left *% element, .saturated = false };
            const value = if (accumulate)
                vectorElement(prior, index, bytes) +% product.value
            else if (subtracting)
                vectorElement(prior, index, bytes) -% product.value
            else
                product.value;
            saturated_any = saturated_any or product.saturated;
            setVectorElement(&result, index, bytes, value);
        }
        if (saturated_any) {
            var status = float_status.FloatStatus.init(self.state.floatStatus());
            status.setSaturated(true);
            self.state.writeFloatStatus(status.raw());
        }
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorWideningMultiplyByElement(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf00f400;
        const signed = masked == 0x0f002000 or masked == 0x0f006000 or masked == 0x0f00a000;
        const signed_saturating_multiply_long = masked == 0x0f00b000;
        const unsigned = masked == 0x2f002000 or masked == 0x2f006000 or masked == 0x2f00a000;
        if (!signed and !signed_saturating_multiply_long and !unsigned) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 0 or size == 3) {
            return error.ReservedInstruction;
        }

        const upper = (word & 0x40000000) != 0;
        const source_bytes = @as(usize, 1) << size;
        const target_bytes = source_bytes * 2;
        const source_bits = @intCast(u8, source_bytes * 8);
        const high = @intCast(usize, (word >> 11) & 1);
        const left_index = @intCast(usize, (word >> 21) & 1);
        const middle_index = @intCast(usize, (word >> 20) & 1);
        const lane_index = if (size == 1)
            (high << 2) | (left_index << 1) | middle_index
        else
            (high << 1) | left_index;
        const element_reg = if (size == 1)
            (word >> 16) & 0xf
        else
            ((word >> 16) & 0xf) | (((word >> 20) & 1) << 4);
        const source_half = if (upper) self.state.readVector(vectorRegFromWord(word >> 5)).high else self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const element = vectorElement(self.state.readVector(vectorRegFromWord(element_reg)), lane_index, source_bytes);
        const right = if (signed or signed_saturating_multiply_long) signExtendRuntime(element, @intCast(u6, source_bits)) else element;
        const source_mask = ones(source_bits);
        const prior = self.state.readVector(vectorRegFromWord(word));
        const accumulating = masked == 0x0f002000 or masked == 0x2f002000;
        const subtracting = masked == 0x0f006000 or masked == 0x2f006000;
        if (signed_saturating_multiply_long) {
            const saturated = signedSaturatingDoublingLongProductHalf(source_half, spreadVectorElement(element, source_bits), source_bits);
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
            const source = (source_half >> shift) & source_mask;
            const left = if (signed) signExtendRuntime(source, @intCast(u6, source_bits)) else source;
            const product = if (signed) @bitCast(u64, @bitCast(i64, left) *% @bitCast(i64, right)) else left *% right;
            const value = if (accumulating)
                vectorElement(prior, index, target_bytes) +% product
            else if (subtracting)
                vectorElement(prior, index, target_bytes) -% product
            else
                product;
            setVectorElement(&result, index, target_bytes, value);
        }
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorDotProduct(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed = masked == 0x0e009400;
        if (!signed and masked != 0x2e009400) {
            return false;
        }

        if (((word >> 22) & 3) != 2) {
            return error.ReservedInstruction;
        }

        const full = (word & 0x40000000) != 0;
        const target = self.state.readVector(vectorRegFromWord(word));
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        self.state.writeVector(vectorRegFromWord(word), accumulateByteDots(target, left, right, full, signed));
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorDotProductByElement(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf00f400;
        const signed = masked == 0x0f00e000;
        if (!signed and masked != 0x2f00e000) {
            return false;
        }

        if (((word >> 22) & 3) != 2) {
            return error.ReservedInstruction;
        }

        const full = (word & 0x40000000) != 0;
        const lane_index = @intCast(usize, ((word >> 21) & 1) | (((word >> 11) & 1) << 1));
        const element_reg = ((word >> 16) & 0xf) | (((word >> 20) & 1) << 4);
        const target = self.state.readVector(vectorRegFromWord(word));
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(element_reg));
        self.state.writeVector(vectorRegFromWord(word), accumulateByteDotsWithLane(target, left, right, full, lane_index, signed));
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorFloatMultiplyByElement(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf00f400;
        const multiply_only = masked == 0x0f009000;
        const extended_multiply = masked == 0x2f009000;
        const accumulate = masked == 0x0f001000;
        const subtract = masked == 0x0f005000;
        if (!multiply_only and !extended_multiply and !accumulate and !subtract) {
            return false;
        }

        const double = (word & 0x00800000) != 0;
        const full = (word & 0x40000000) != 0;
        const left_index = @intCast(usize, (word >> 22) & 1);
        const middle_index = @intCast(usize, (word >> 21) & 1);
        const high = @intCast(usize, (word >> 11) & 1);
        if (double and left_index != 0) {
            return error.ReservedInstruction;
        }
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const lanes = if (double) @as(usize, 2) else if (full) @as(usize, 4) else @as(usize, 2);
        const lane_index = if (double) high else (high << 1) | left_index;
        const element_reg = ((word >> 16) & 0xf) | (middle_index << 4);
        const element = vectorElement(self.state.readVector(vectorRegFromWord(element_reg)), lane_index, bytes);
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const control = self.state.floatControl();
        const nan_mode = self.hooks.float_nan_mode;
        const prior = self.state.readVector(vectorRegFromWord(word));
        var result = a64_state.VectorValue{ .low = 0, .high = 0 };
        if (multiply_only or extended_multiply) {
            var index: usize = 0;
            while (index < lanes) : (index += 1) {
                const left = vectorElement(source, index, bytes);
                const value = if (extended_multiply)
                    floatMulExtended(control, nan_mode, double, left, element)
                else
                    floatMul(control, nan_mode, double, left, element);
                setVectorElement(&result, index, bytes, value);
            }
        } else {
            const fused_control = effectiveFloatControl(control, nan_mode);
            var status = float_status.FloatStatus.init(self.state.floatStatus());
            var index: usize = 0;
            while (index < lanes) : (index += 1) {
                const addend = vectorElement(prior, index, bytes);
                const left = vectorElement(source, index, bytes);
                const adjusted_left = if (subtract) negateFloat(double, left) else left;
                const value = if (double)
                    float_fused.mulAdd64(addend, adjusted_left, element, fused_control, &status) catch return error.MissingFallback
                else
                    @as(u64, float_fused.mulAdd32(@intCast(u32, addend), @intCast(u32, adjusted_left), @intCast(u32, element), fused_control, &status) catch return error.MissingFallback);
                setVectorElement(&result, index, bytes, value);
            }
            self.state.writeFloatStatus(status.raw());
        }
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarFloatMultiplyByElement(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff00f400;
        const multiply_only = masked == 0x5f009000;
        const extended_multiply = masked == 0x7f009000;
        const accumulate = masked == 0x5f001000;
        const subtract = masked == 0x5f005000;
        if (!multiply_only and !extended_multiply and !accumulate and !subtract) {
            return false;
        }

        const double = (word & 0x00800000) != 0;
        const left_index = @intCast(usize, (word >> 22) & 1);
        const middle_index = @intCast(usize, (word >> 21) & 1);
        const high = @intCast(usize, (word >> 11) & 1);
        if (double and left_index != 0) {
            return error.ReservedInstruction;
        }

        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const lane_index = if (double) high else (high << 1) | left_index;
        const element_reg = ((word >> 16) & 0xf) | (middle_index << 4);
        const source = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const element = vectorElement(self.state.readVector(vectorRegFromWord(element_reg)), lane_index, bytes);
        const result = if (multiply_only or extended_multiply)
            if (extended_multiply)
                floatMulExtended(self.state.floatControl(), self.hooks.float_nan_mode, double, source, element)
            else
                floatMul(self.state.floatControl(), self.hooks.float_nan_mode, double, source, element)
        else blk: {
            const control = effectiveFloatControl(self.state.floatControl(), self.hooks.float_nan_mode);
            var status = float_status.FloatStatus.init(self.state.floatStatus());
            const addend = vectorElement(self.state.readVector(vectorRegFromWord(word)), 0, bytes);
            const left = if (subtract) negateFloat(double, source) else source;
            const value = if (double)
                float_fused.mulAdd64(addend, left, element, control, &status) catch return error.MissingFallback
            else
                @as(u64, float_fused.mulAdd32(@intCast(u32, addend), @intCast(u32, left), @intCast(u32, element), control, &status) catch return error.MissingFallback);
            self.state.writeFloatStatus(status.raw());
            break :blk value;
        };
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarMultiplyHighByElement(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff00f400;
        const multiply_long = masked == 0x5f00b000;
        const multiply_high = masked == 0x5f00c000;
        const rounding_multiply_high = masked == 0x5f00d000;
        if (!multiply_long and !multiply_high and !rounding_multiply_high) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 0 or size == 3) {
            return error.ReservedInstruction;
        }

        const bytes = @as(usize, 1) << size;
        const high = @intCast(usize, (word >> 11) & 1);
        const left_index = @intCast(usize, (word >> 21) & 1);
        const middle_index = @intCast(usize, (word >> 20) & 1);
        const lane_index = if (size == 1)
            (high << 2) | (left_index << 1) | middle_index
        else
            (high << 1) | left_index;
        const element_reg = if (size == 1)
            (word >> 16) & 0xf
        else
            ((word >> 16) & 0xf) | (((word >> 20) & 1) << 4);
        const source = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const element = vectorElement(self.state.readVector(vectorRegFromWord(element_reg)), lane_index, bytes);
        const width = @intCast(u8, bytes * 8);
        if (multiply_long) {
            const saturated = signedSaturatingDoublingLongProductHalf(source, spreadVectorElement(element, width), width);
            if (saturated.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), saturated.value);
            self.state.pc +%= 4;
            return true;
        }
        const result = if (rounding_multiply_high) blk: {
            const parts = signedSaturatingDoublingProductParts64(source, element, width);
            const value = (parts.high +% (parts.low >> @intCast(u6, width - 1))) & ones(width);
            break :blk SaturatingIntegerResult{ .value = value, .saturated = parts.saturated };
        } else signedSaturatedDoublingMultiplyHigh(width, source, element);
        if (result.saturated) {
            var status = float_status.FloatStatus.init(self.state.floatStatus());
            status.setSaturated(true);
            self.state.writeFloatStatus(status.raw());
        }
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result.value, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }
};
