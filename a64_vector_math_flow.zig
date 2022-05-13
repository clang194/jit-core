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
    pub fn runVectorFloatNegate(self: *Core64, word: u32) Core64Error!bool {
        const half = (word & 0xbffffc00) == 0x2ef8f800;
        const half_absolute = (word & 0xbffffc00) == 0x0ef8f800;
        const wide = (word & 0xbf3ffc00) == 0x2e20f800;
        const absolute = (word & 0xbfbffc00) == 0x0ea0f800;
        if (!half and !half_absolute and !wide and !absolute) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = ((word >> 22) & 1) != 0;
        if ((wide or absolute) and double and !full) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = if (half) negateHalfFloatVector(full, source) else if (half_absolute) absoluteHalfFloatVector(full, source) else if (absolute) absoluteFloatVector(double, full, source) else negateFloatVector(double, full, source);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorFloatBinary(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbfa0fc00;
        if (masked != 0x0e20d400 and masked != 0x0ea0d400 and masked != 0x2e20dc00 and masked != 0x2e20fc00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = ((word >> 22) & 1) != 0;
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const control = self.state.floatControl();
        const nan_mode = self.hooks.float_nan_mode;
        const result = if (masked == 0x0e20d400)
            addFloatVector(control, nan_mode, double, full, left, right)
        else if (masked == 0x2e20dc00)
            multiplyFloatVector(control, nan_mode, double, full, left, right)
        else if (masked == 0x2e20fc00)
            divideFloatVector(control, nan_mode, double, full, left, right)
        else
            subtractFloatVector(control, nan_mode, double, full, left, right);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorSignedIntegerToFloat(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfbffc00) != 0x0e21d800) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const double = ((word >> 22) & 1) != 0;
        if (double and !full) {
            return error.ReservedInstruction;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const result = if (double)
            signedDoublewordsToFloatVector(source)
        else
            signedWordsToFloatVector(full, source);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorShiftImmediate(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf80fc00;
        if (masked != 0x0f000400 and masked != 0x0f001400 and masked != 0x0f002400 and masked != 0x0f003400 and masked != 0x0f005400 and masked != 0x0f008400 and masked != 0x0f008c00 and masked != 0x0f00a400 and masked != 0x2f000400 and masked != 0x2f001400 and masked != 0x2f002400 and masked != 0x2f003400 and masked != 0x2f004400 and masked != 0x2f005400 and masked != 0x2f00a400) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const immh = @intCast(u4, (word >> 19) & 0xf);
        if (immh == 0) {
            return error.UnallocatedEncoding;
        }
        if (masked == 0x0f008400 or masked == 0x0f008c00) {
            if ((immh & 8) != 0) {
                return error.ReservedInstruction;
            }

            const target_lane = @as(u8, 8) << @intCast(u3, highestSetBit(immh));
            const source_lane = target_lane * 2;
            const immediate = @intCast(u8, (word >> 16) & 0x7f);
            const amount = source_lane - immediate;
            const source = self.state.readVector(vectorRegFromWord(word >> 5));
            const narrowed = if (masked == 0x0f008400)
                narrowShiftRightVectorLanes(source, @intCast(usize, target_lane / 8), amount)
            else
                narrowRoundedShiftRightVectorLanes(source, @intCast(usize, target_lane / 8), amount);
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
        const right = signed_right or rounded_signed_right or rounded_right or insert_right or masked == 0x2f000400 or masked == 0x2f001400;
        const amount = if (right)
            @intCast(u8, @as(u16, lane) * 2 - immediate)
        else
            immediate - @intCast(u8, lane);
        const input = self.state.readVector(vectorRegFromWord(word >> 5));
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
        if (masked != 0x5f000400 and masked != 0x5f001400 and masked != 0x5f002400 and masked != 0x5f003400 and masked != 0x5f005400 and masked != 0x7f000400 and masked != 0x7f001400 and masked != 0x7f002400 and masked != 0x7f003400 and masked != 0x7f004400 and masked != 0x7f005400) {
            return false;
        }

        const immh = @intCast(u4, (word >> 19) & 0xf);
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

    pub fn runScalarVectorArithmetic(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff20fc00;
        if (masked != 0x5e203400 and masked != 0x5e203c00 and masked != 0x5e204400 and masked != 0x5e208400 and masked != 0x5e208c00 and masked != 0x7e203400 and masked != 0x7e203c00 and masked != 0x7e204400 and masked != 0x7e208400 and masked != 0x7e208c00) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size != 3) {
            return error.ReservedInstruction;
        }

        const left = self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const right = self.state.readVector(vectorRegFromWord(word >> 16)).low;
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
        else if (masked == 0x7e204400)
            variableUnsignedShiftVectorLanes(left, right, 64)
        else
            0;
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runScalarPairAdd(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xff20fc00) != 0x5e20bc00) {
            return false;
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
        if (masked != 0x0e200400 and masked != 0x0e202400 and masked != 0x0e208400 and masked != 0x0e209400 and masked != 0x0e209c00 and masked != 0x2e200400 and masked != 0x2e202400 and masked != 0x2e208400 and masked != 0x2e209400) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and (masked == 0x0e200400 or masked == 0x0e202400 or masked == 0x0e209400 or masked == 0x0e209c00 or masked == 0x2e200400 or masked == 0x2e202400 or masked == 0x2e209400 or !full)) {
            return error.ReservedInstruction;
        }

        const lane = @as(u8, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = if (masked == 0x0e209400 or masked == 0x2e209400) blk: {
            const prior = self.state.readVector(vectorRegFromWord(word));
            break :blk a64_state.VectorValue{
                .low = if (masked == 0x0e209400) addVectorLanes(prior.low, multiplyVectorLanes(left.low, right.low, lane), lane) else subtractVectorLanes(prior.low, multiplyVectorLanes(left.low, right.low, lane), lane),
                .high = if (full) if (masked == 0x0e209400) addVectorLanes(prior.high, multiplyVectorLanes(left.high, right.high, lane), lane) else subtractVectorLanes(prior.high, multiplyVectorLanes(left.high, right.high, lane), lane) else 0,
            };
        } else a64_state.VectorValue{
            .low = if (masked == 0x0e200400) signedHalvingAddVectorLanes(left.low, right.low, lane) else if (masked == 0x0e202400) signedHalvingSubtractVectorLanes(left.low, right.low, lane) else if (masked == 0x2e200400) halvingAddVectorLanes(left.low, right.low, lane) else if (masked == 0x2e202400) halvingSubtractVectorLanes(left.low, right.low, lane) else if (masked == 0x0e208400) addVectorLanes(left.low, right.low, lane) else if (masked == 0x0e209c00) multiplyVectorLanes(left.low, right.low, lane) else subtractVectorLanes(left.low, right.low, lane),
            .high = if (full) if (masked == 0x0e200400) signedHalvingAddVectorLanes(left.high, right.high, lane) else if (masked == 0x0e202400) signedHalvingSubtractVectorLanes(left.high, right.high, lane) else if (masked == 0x2e200400) halvingAddVectorLanes(left.high, right.high, lane) else if (masked == 0x2e202400) halvingSubtractVectorLanes(left.high, right.high, lane) else if (masked == 0x0e208400) addVectorLanes(left.high, right.high, lane) else if (masked == 0x0e209c00) multiplyVectorLanes(left.high, right.high, lane) else subtractVectorLanes(left.high, right.high, lane) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorMultiplyAddByElement(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf00f400;
        const multiply_only = masked == 0x0f008000;
        const accumulate = masked == 0x2f000000;
        const subtracting = masked == 0x2f004000;
        if (!multiply_only and !accumulate and !subtracting) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 0 or size == 3) {
            return error.UnallocatedEncoding;
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
        var index: usize = 0;
        while (index < total / bytes) : (index += 1) {
            const product = vectorElement(source, index, bytes) *% element;
            const value = if (accumulate)
                vectorElement(prior, index, bytes) +% product
            else if (subtracting)
                vectorElement(prior, index, bytes) -% product
            else
                product;
            setVectorElement(&result, index, bytes, value);
        }
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorWideningArithmetic(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed_difference = masked == 0x0e205000 or masked == 0x0e207000;
        const signed_multiply_long = masked == 0x0e20c000;
        const signed = masked == 0x0e200000 or masked == 0x0e201000 or masked == 0x0e202000 or masked == 0x0e203000 or signed_difference or signed_multiply_long;
        const subtracting = masked == 0x0e202000 or masked == 0x0e203000 or masked == 0x2e202000 or masked == 0x2e203000;
        const widening_source_pair = masked == 0x0e200000 or masked == 0x0e202000 or masked == 0x2e200000 or masked == 0x2e202000;
        const accumulating_difference = masked == 0x0e205000 or masked == 0x2e205000;
        const absolute_difference = masked == 0x0e207000 or masked == 0x2e207000 or accumulating_difference;
        if (!signed and masked != 0x2e201000 and masked != 0x2e203000 and !widening_source_pair and !absolute_difference) {
            return false;
        }

        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3) {
            return error.ReservedInstruction;
        }

        const upper = (word & 0x40000000) != 0;
        const source_bytes = @as(usize, 1) << size;
        const target_bytes = source_bytes * 2;
        const source_bits = @intCast(u8, source_bytes * 8);
        const source_mask = ones(source_bits);
        const addend = self.state.readVector(vectorRegFromWord(word >> 16));
        const addend_half = if (upper) addend.high else addend.low;
        const base = self.state.readVector(vectorRegFromWord(word >> 5));
        const base_half = if (upper) base.high else base.low;
        var result = a64_state.VectorValue{ .low = 0, .high = 0 };
        var index: usize = 0;
        while (index < 8 / source_bytes) : (index += 1) {
            const shift = @intCast(u6, index * source_bytes * 8);
            const raw_left = (base_half >> shift) & source_mask;
            const left = if (widening_source_pair or absolute_difference or signed_multiply_long) if (signed) signExtendRuntime(raw_left, @intCast(u6, source_bits)) else raw_left else vectorElement(base, index, target_bytes);
            const raw = (addend_half >> shift) & source_mask;
            const right = if (signed) signExtendRuntime(raw, @intCast(u6, source_bits)) else raw;
            const difference = if (signed_difference) blk: {
                const signed_left = @bitCast(i64, left);
                const signed_right = @bitCast(i64, right);
                break :blk @bitCast(u64, if (signed_left >= signed_right) signed_left - signed_right else signed_right - signed_left);
            } else if (left >= right) left - right else right - left;
            const value = if (signed_multiply_long) @bitCast(u64, @bitCast(i64, left) *% @bitCast(i64, right)) else if (accumulating_difference) vectorElement(self.state.readVector(vectorRegFromWord(word)), index, target_bytes) +% difference else if (absolute_difference) difference else if (subtracting) left -% right else left +% right;
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

    pub fn runVectorPairAdd(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf20fc00) != 0x0e20bc00) {
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

    pub fn runVectorUnsignedShift(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xbf20fc00;
        const signed = masked == 0x0e204400;
        if (!signed and masked != 0x2e204400) {
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
            .low = if (signed) variableSignedShiftVectorLanes(left.low, right.low, lane) else variableUnsignedShiftVectorLanes(left.low, right.low, lane),
            .high = if (full) if (signed) variableSignedShiftVectorLanes(left.high, right.high, lane) else variableUnsignedShiftVectorLanes(left.high, right.high, lane) else 0,
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
