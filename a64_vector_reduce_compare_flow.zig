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
    pub fn runVectorPairAdd(self: *Core64, word: u32) Core64Error!bool {
        const pattern = word & 0xbf20fc00;
        const paired = pattern == 0x0e20bc00;
        const wide_signed = pattern == 0x0e202800;
        const wide_unsigned = pattern == 0x2e202800;
        const accumulating_signed = pattern == 0x0e203800;
        const accumulating_unsigned = pattern == 0x2e203800;
        const wide = wide_signed or wide_unsigned or accumulating_signed or accumulating_unsigned;
        if (!paired and !wide) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if ((wide and size == 3) or (paired and size == 3 and !full)) {
            return error.ReservedInstruction;
        }

        if (wide) {
            const bytes = @as(usize, 1) << @intCast(u6, size);
            const total = if (full) @as(usize, 16) else @as(usize, 8);
            const source = self.state.readVector(vectorRegFromWord(word >> 5));
            var result = pairwiseAddWideVector(source, bytes, total, wide_signed or accumulating_signed);
            if (accumulating_signed or accumulating_unsigned) {
                const target = self.state.readVector(vectorRegFromWord(word));
                const lane = @as(u8, 16) << @intCast(u3, size);
                result = a64_state.VectorValue{
                    .low = addVectorLanes(target.low, result.low, lane),
                    .high = if (full) addVectorLanes(target.high, result.high, lane) else 0,
                };
            }
            self.state.writeVector(vectorRegFromWord(word), result);
            self.state.pc +%= 4;
            return true;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = if (full)
            a64_state.VectorValue{
                .low = pairVectorHalves(left.low, left.high, lane),
                .high = pairVectorHalves(right.low, right.high, lane),
            }
        else
            a64_state.VectorValue{
                .low = pairVectorHalves(left.low, right.low, lane),
                .high = 0,
            };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorPairExtrema(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed_max = masked == 0x0e20a400;
        const signed_min = masked == 0x0e20ac00;
        const unsigned_max = masked == 0x2e20a400;
        const unsigned_min = masked == 0x2e20ac00;
        if (!signed_max and !signed_min and !unsigned_max and !unsigned_min) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3) {
            return error.ReservedInstruction;
        }

        const full = (word & 0x40000000) != 0;
        const lane = @as(u8, 8) << @intCast(u3, size);
        const signed = signed_max or signed_min;
        const maximum = signed_max or unsigned_max;
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = if (full)
            a64_state.VectorValue{
                .low = pairVectorExtrema(left.low, left.high, lane, signed, maximum),
                .high = pairVectorExtrema(right.low, right.high, lane, signed, maximum),
            }
        else
            a64_state.VectorValue{
                .low = pairVectorExtrema(left.low, right.low, lane, signed, maximum),
                .high = 0,
            };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorEqual(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf20fc00) != 0x2e208c00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = a64_state.VectorValue{
            .low = equalVectorLanes(left.low, right.low, lane),
            .high = if (full) equalVectorLanes(left.high, right.high, lane) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorSharedBitCompare(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf20fc00) != 0x0e208c00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = a64_state.VectorValue{
            .low = sharedBitVectorLanes(left.low, right.low, lane),
            .high = if (full) sharedBitVectorLanes(left.high, right.high, lane) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorGreaterSigned(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const strict = masked == 0x0e203400;
        const inclusive = masked == 0x0e203c00;
        if (!strict and !inclusive) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = a64_state.VectorValue{
            .low = greaterSignedVectorLanes(left.low, right.low, lane, inclusive),
            .high = if (full) greaterSignedVectorLanes(left.high, right.high, lane, inclusive) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorGreaterUnsigned(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const strict = masked == 0x2e203400;
        const inclusive = masked == 0x2e203c00;
        if (!strict and !inclusive) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = a64_state.VectorValue{
            .low = greaterUnsignedVectorLanes(left.low, right.low, lane, inclusive),
            .high = if (full) greaterUnsignedVectorLanes(left.high, right.high, lane, inclusive) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorVariableShift(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed = masked == 0x0e204400;
        const signed_saturating = masked == 0x0e204c00;
        const unsigned_saturating = masked == 0x2e204c00;
        const rounded_signed = masked == 0x0e205400;
        const rounded_unsigned = masked == 0x2e205400;
        if (!signed and !signed_saturating and !unsigned_saturating and !rounded_signed and masked != 0x2e204400 and !rounded_unsigned) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        if (signed_saturating) {
            const low = variableSignedSaturatingShiftLeftVectorLanes(left.low, right.low, lane);
            const high = if (full) variableSignedSaturatingShiftLeftVectorLanes(left.high, right.high, lane) else SaturatingShiftResult{ .value = 0, .saturated = false };
            if (low.saturated or high.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = low.value, .high = high.value });
            self.state.pc +%= 4;
            return true;
        }
        if (unsigned_saturating) {
            const low = variableUnsignedSaturatingShiftLeftVectorLanes(left.low, right.low, lane);
            const high = if (full) variableUnsignedSaturatingShiftLeftVectorLanes(left.high, right.high, lane) else SaturatingShiftResult{ .value = 0, .saturated = false };
            if (low.saturated or high.saturated) {
                var status = float_status.FloatStatus.init(self.state.floatStatus());
                status.setSaturated(true);
                self.state.writeFloatStatus(status.raw());
            }
            self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = low.value, .high = high.value });
            self.state.pc +%= 4;
            return true;
        }
        const result = a64_state.VectorValue{
            .low = if (signed) variableSignedShiftVectorLanes(left.low, right.low, lane) else if (rounded_signed) variableRoundedSignedShiftVectorLanes(left.low, right.low, lane) else if (rounded_unsigned) variableRoundedUnsignedShiftVectorLanes(left.low, right.low, lane) else variableUnsignedShiftVectorLanes(left.low, right.low, lane),
            .high = if (full) if (signed) variableSignedShiftVectorLanes(left.high, right.high, lane) else if (rounded_signed) variableRoundedSignedShiftVectorLanes(left.high, right.high, lane) else if (rounded_unsigned) variableRoundedUnsignedShiftVectorLanes(left.high, right.high, lane) else variableUnsignedShiftVectorLanes(left.high, right.high, lane) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorMinMax(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed_max = masked == 0x0e206400;
        const signed_min = masked == 0x0e206c00;
        const unsigned_max = masked == 0x2e206400;
        const unsigned_min = masked == 0x2e206c00;
        if (!signed_max and !signed_min and !unsigned_max and !unsigned_min) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3) {
            return error.ReservedInstruction;
        }

        const full = (word & 0x40000000) != 0;
        const lane = @as(u8, 8) << @intCast(u3, size);
        const signed = signed_max or signed_min;
        const maximum = signed_max or unsigned_max;
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = a64_state.VectorValue{
            .low = minMaxVectorLanes(left.low, right.low, lane, signed, maximum),
            .high = if (full) minMaxVectorLanes(left.high, right.high, lane, signed, maximum) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorAcrossMinMax(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf3ffc00;
        const signed_max = masked == 0x0e30a800;
        const signed_min = masked == 0x0e31a800;
        const unsigned_max = masked == 0x2e30a800;
        const unsigned_min = masked == 0x2e31a800;
        if (!signed_max and !signed_min and !unsigned_max and !unsigned_min) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        const full = (word & 0x40000000) != 0;
        if ((size == 2 and !full) or size == 3) {
            return error.ReservedInstruction;
        }

        const bytes = @as(usize, 1) << @intCast(u3, size);
        const lanes = (if (full) @as(usize, 16) else @as(usize, 8)) / bytes;
        const signed = signed_max or signed_min;
        const maximum = signed_max or unsigned_max;
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        var value = if (signed) signExtendRuntime(vectorElement(source, 0, bytes), @intCast(u6, bytes * 8)) else vectorElement(source, 0, bytes);
        var index: usize = 1;
        while (index < lanes) : (index += 1) {
            const element = if (signed) signExtendRuntime(vectorElement(source, index, bytes), @intCast(u6, bytes * 8)) else vectorElement(source, index, bytes);
            value = if (maximum) integerMaximum(false, signed, value, element) else integerMinimum(false, signed, value, element);
        }

        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = value & ones(@intCast(u8, bytes * 8)), .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorAcrossAdd(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf3ffc00;
        const narrow = masked == 0x0e31b800;
        const signed_wide = masked == 0x0e303800;
        const unsigned_wide = masked == 0x2e303800;
        const wide = signed_wide or unsigned_wide;
        if (!narrow and !wide) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        const full = (word & 0x40000000) != 0;
        if ((size == 2 and !full) or size == 3) {
            return error.ReservedInstruction;
        }

        const bytes = @as(usize, 1) << @intCast(u3, size);
        const lanes = (if (full) @as(usize, 16) else @as(usize, 8)) / bytes;
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        var sum: u64 = 0;
        var index: usize = 0;
        while (index < lanes) : (index += 1) {
            const element = vectorElement(source, index, bytes);
            sum +%= if (signed_wide) signExtendRuntime(element, @intCast(u6, bytes * 8)) else element;
        }

        const result = if (wide)
            if (size == 0) sum & 0xffff else if (size == 1) sum & 0xffffffff else sum
        else
            sum & if (size == 0) @as(u64, 0xff) else if (size == 1) @as(u64, 0xffff) else @as(u64, 0xffffffff);
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }
};
