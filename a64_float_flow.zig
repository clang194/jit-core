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
    pub fn runFloatImmediate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xff201fe0) != 0x1e201000) {
            return false;
        }

        const mode = @intCast(u2, (word >> 22) & 3);
        const encoded = @intCast(u8, (word >> 13) & 0xff);
        const value = switch (mode) {
            0 => @as(u64, expandFloatConstant32(encoded)),
            1 => expandFloatConstant64(encoded),
            3 => @as(u64, expandFloatConstant16(encoded)),
            else => return error.UnallocatedEncoding,
        };
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = value, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runFloatUnary(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff3ffc00;
        if (masked != 0x1e204000 and masked != 0x1e20c000 and masked != 0x1e214000 and masked != 0x1e21c000) {
            return false;
        }

        const mode = @intCast(u2, (word >> 22) & 3);
        if (mode > 1) {
            return error.UnallocatedEncoding;
        }

        const source = self.state.readVector(vectorRegFromWord(word >> 5)).low;
        const result = if (masked == 0x1e21c000)
            floatSqrt(self.state.floatControl(), self.hooks.float_nan_mode, mode == 1, source)
        else if (mode == 1)
            if (masked == 0x1e204000) source else if (masked == 0x1e20c000) source & 0x7fffffffffffffff else source ^ 0x8000000000000000
        else
            @as(u64, if (masked == 0x1e204000) @intCast(u32, source) else if (masked == 0x1e20c000) @intCast(u32, source) & 0x7fffffff else @intCast(u32, source) ^ 0x80000000);
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runFloatConvert(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xff3e7c00) != 0x1e224000) {
            return false;
        }

        const source_mode = @intCast(u2, (word >> 22) & 3);
        const target_mode = @intCast(u2, (word >> 15) & 3);
        if (source_mode == 2 or target_mode == 2 or source_mode == target_mode) {
            return error.UnallocatedEncoding;
        }
        if (source_mode == 3 or target_mode == 3) {
            return false;
        }

        const control = self.state.floatControl();
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const value = if (source_mode == 0)
            float32To64(control, @intCast(u32, source.low))
        else
            @as(u64, float64To32(control, source.low));
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = value, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runIntegerToFloat(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0x7f3ffc00;
        if (masked != 0x1e220000 and masked != 0x1e230000) {
            return false;
        }

        const mode = @intCast(u2, (word >> 22) & 3);
        if (mode > 1) {
            return error.UnallocatedEncoding;
        }
        const wide = (word & 0x80000000) != 0;
        if (wide and mode == 0) {
            return false;
        }

        const input = self.readSized(wide, regFromWord(word >> 5), false);
        const result = if (mode == 0)
            @as(u64, if (masked == 0x1e220000) signedWordToFloat32(@intCast(u32, input)) else unsignedWordToFloat32(@intCast(u32, input)))
        else if (wide)
            if (masked == 0x1e220000) signedDoublewordToFloat64(input) else unsignedDoublewordToFloat64(input)
        else if (masked == 0x1e220000) signedWordToFloat64(@intCast(u32, input)) else unsignedWordToFloat64(@intCast(u32, input));
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runFloatGeneralMove(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x7f36fc00) != 0x1e260000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const mode = @intCast(u2, (word >> 22) & 3);
        const upper = ((word >> 19) & 1) != 0;
        const to_vector = ((word >> 16) & 1) != 0;
        const bytes: usize = switch (mode) {
            0 => 4,
            1 => 8,
            2 => if (upper) @as(usize, 8) else return error.UnallocatedEncoding,
            else => return error.UnallocatedEncoding,
        };

        if (upper) {
            if (!wide or mode != 2) {
                return error.UnallocatedEncoding;
            }
        } else if (wide != (bytes == 8)) {
            return error.UnallocatedEncoding;
        }

        if (to_vector) {
            const value = self.readSized(wide, regFromWord(word >> 5), false);
            if (upper) {
                var result = self.state.readVector(vectorRegFromWord(word));
                result.high = value;
                self.state.writeVector(vectorRegFromWord(word), result);
            } else {
                self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = value & ones(@intCast(u8, bytes * 8)), .high = 0 });
            }
        } else {
            const source = self.state.readVector(vectorRegFromWord(word >> 5));
            const value = if (upper) source.high else vectorElement(source, 0, bytes);
            self.writeSized(wide, regFromWord(word), value, false);
        }

        self.state.pc +%= 4;
        return true;
    }

    pub fn runFixedToInteger(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0x7f3f0000;
        if (masked != 0x1e180000 and masked != 0x1e190000) {
            return false;
        }

        const mode = @intCast(u2, (word >> 22) & 3);
        if (mode == 2 or mode == 3) {
            return error.UnallocatedEncoding;
        }

        const wide = (word & 0x80000000) != 0;
        const scale = @intCast(u6, (word >> 10) & 0x3f);
        if (!wide and (scale & 0x20) == 0) {
            return error.UnallocatedEncoding;
        }
        if (wide) {
            return false;
        }

        const double = mode == 1;
        const fraction = @as(u8, 64) - scale;
        const factor = if (double)
            (@as(u64, fraction + 1023) << 52)
        else
            @as(u64, @as(u32, fraction + 127) << 23);
        const control = self.state.floatControl();
        const scaled = floatMul(control, self.hooks.float_nan_mode, double, vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, if (double) @as(usize, 8) else @as(usize, 4)), factor);
        const result = if (masked == 0x1e180000)
            floatToSignedWord(control, double, scaled)
        else
            floatToUnsignedWord(control, double, scaled);
        self.writeSized(false, regFromWord(word), @as(u64, result), false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runFloatToInteger(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0x7f3ffc00;
        if (masked != 0x1e380000 and masked != 0x1e390000) {
            return false;
        }

        const mode = @intCast(u2, (word >> 22) & 3);
        if (mode > 1) {
            return error.UnallocatedEncoding;
        }
        if ((word & 0x80000000) != 0) {
            return false;
        }

        const control = self.state.floatControl();
        const input = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, if (mode == 1) @as(usize, 8) else @as(usize, 4));
        const result = if (masked == 0x1e380000)
            floatToSignedWord(control, mode == 1, input)
        else
            floatToUnsignedWord(control, mode == 1, input);
        self.writeSized(false, regFromWord(word), @as(u64, result), false);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runFloatBinary(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff20fc00;
        if (masked != 0x1e200800 and masked != 0x1e201800 and masked != 0x1e202800 and masked != 0x1e203800 and masked != 0x1e204800 and masked != 0x1e205800 and masked != 0x1e206800 and masked != 0x1e207800 and masked != 0x1e208800) {
            return false;
        }

        const mode = (word >> 22) & 3;
        if (mode > 1) {
            return error.UnallocatedEncoding;
        }

        const double = mode == 1;
        const control = self.state.floatControl();
        const nan_mode = self.hooks.float_nan_mode;
        const left = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, if (double) @as(usize, 8) else @as(usize, 4));
        const right = vectorElement(self.state.readVector(vectorRegFromWord(word >> 16)), 0, if (double) @as(usize, 8) else @as(usize, 4));
        const result = switch (masked) {
            0x1e200800 => floatMul(control, nan_mode, double, left, right),
            0x1e201800 => floatDiv(control, nan_mode, double, left, right),
            0x1e202800 => floatAdd(control, nan_mode, double, left, right),
            0x1e203800 => floatSub(control, nan_mode, double, left, right),
            0x1e204800 => floatMax(control, nan_mode, double, left, right),
            0x1e205800 => floatMin(control, nan_mode, double, left, right),
            0x1e206800 => floatMaxNumber(control, nan_mode, double, left, right),
            0x1e207800 => floatMinNumber(control, nan_mode, double, left, right),
            else => negateFloat(double, floatMul(control, nan_mode, double, left, right)),
        };
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runFloatMulAdd(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xff000000) != 0x1f000000) {
            return false;
        }

        const negated_addend = (word & 0x00200000) != 0;
        const subtract = (word & 0x8000) != 0;

        const mode = (word >> 22) & 3;
        if (mode > 1) {
            return error.UnallocatedEncoding;
        }

        const double = mode == 1;
        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const addend = vectorElement(self.state.readVector(vectorRegFromWord(word >> 10)), 0, bytes);
        const left = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const right = vectorElement(self.state.readVector(vectorRegFromWord(word >> 16)), 0, bytes);
        const adjusted_addend = if (negated_addend) negateFloat(double, addend) else addend;
        const adjusted_left = if (negated_addend != subtract) negateFloat(double, left) else left;
        const result = floatMulAdd(self.state.floatControl(), self.hooks.float_nan_mode, double, adjusted_addend, adjusted_left, right);
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    pub fn runFloatCompare(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff20fc17;
        if (masked != 0x1e202000 and masked != 0x1e202010) {
            return false;
        }

        const mode = (word >> 22) & 3;
        if (mode > 1) {
            return error.UnallocatedEncoding;
        }

        const double = mode == 1;
        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const control = self.state.floatControl();
        const left = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const right = if ((word & 0x8) != 0) @as(u64, 0) else vectorElement(self.state.readVector(vectorRegFromWord(word >> 16)), 0, bytes);
        self.state.writeNzcv(compareFloat(control, double, left, right));
        self.state.pc +%= 4;
        return true;
    }

    pub fn runFloatConditionalCompare(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xff200c00) != 0x1e200400) {
            return false;
        }

        const mode = @intCast(u2, (word >> 22) & 3);
        if (mode > 1) {
            return error.UnallocatedEncoding;
        }

        if (self.conditionHolds(@intCast(u4, (word >> 12) & 0xf))) {
            const double = mode == 1;
            const bytes = if (double) @as(usize, 8) else @as(usize, 4);
            const control = self.state.floatControl();
            const left = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
            const right = vectorElement(self.state.readVector(vectorRegFromWord(word >> 16)), 0, bytes);
            self.state.writeNzcv(compareFloat(control, double, left, right));
        } else {
            self.state.writeNzcv(@as(u32, word & 0xf) << 28);
        }

        self.state.pc +%= 4;
        return true;
    }

    pub fn runFloatSelect(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xff200c00) != 0x1e200c00) {
            return false;
        }

        const mode = @intCast(u2, (word >> 22) & 3);
        if (mode > 1) {
            return error.UnallocatedEncoding;
        }

        const bytes = if (mode == 1) @as(usize, 8) else @as(usize, 4);
        const left = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const right = vectorElement(self.state.readVector(vectorRegFromWord(word >> 16)), 0, bytes);
        const result = if (self.conditionHolds(@intCast(u4, (word >> 12) & 0xf))) left else right;
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }
};
