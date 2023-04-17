pub const Binary16 = struct {
    pub const total_bits: usize = 16;
    pub const exponent_bits: usize = 5;
    pub const stored_fraction_bits: usize = 10;
    pub const precision_bits: usize = stored_fraction_bits + 1;
    pub const hidden_bit: u16 = @as(u16, 1) << stored_fraction_bits;
    pub const sign_mask: u16 = 0x8000;
    pub const exponent_mask: u16 = 0x7c00;
    pub const fraction_mask: u16 = 0x03ff;
    pub const fraction_top_bit: u16 = 0x0200;
    pub const exponent_min: i32 = -14;
    pub const exponent_max: i32 = 15;
    pub const exponent_bias: u16 = 15;

    pub fn zero(negative: bool) u16 {
        return if (negative) sign_mask else 0;
    }

    pub fn infinity(negative: bool) u16 {
        return exponent_mask | zero(negative);
    }

    pub fn maxNormal(negative: bool) u16 {
        return (exponent_mask - 1) | zero(negative);
    }

    pub fn defaultNan() u16 {
        return exponent_mask | fraction_top_bit;
    }

    pub fn finite(comptime negative: bool, comptime exponent: i32, comptime significand: u16) u16 {
        if (significand == 0) {
            return zero(negative);
        }

        const highest = @intCast(i32, 15 - @clz(significand));
        const offset = @intCast(i32, stored_fraction_bits) - highest;
        const normalized_exponent = exponent - offset + @intCast(i32, stored_fraction_bits);
        if (offset < 0 or normalized_exponent < exponent_min or normalized_exponent > exponent_max) {
            @compileError("invalid finite value");
        }

        const fraction = (significand << @intCast(u4, offset)) & fraction_mask;
        const biased_exponent = @intCast(u16, normalized_exponent + @intCast(i32, exponent_bias));
        return zero(negative) | fraction | (biased_exponent << stored_fraction_bits);
    }
};

pub const Binary32 = struct {
    pub const total_bits: usize = 32;
    pub const exponent_bits: usize = 8;
    pub const stored_fraction_bits: usize = 23;
    pub const precision_bits: usize = stored_fraction_bits + 1;
    pub const hidden_bit: u32 = @as(u32, 1) << stored_fraction_bits;
    pub const sign_mask: u32 = 0x80000000;
    pub const exponent_mask: u32 = 0x7f800000;
    pub const fraction_mask: u32 = 0x007fffff;
    pub const fraction_top_bit: u32 = 0x00400000;
    pub const exponent_min: i32 = -126;
    pub const exponent_max: i32 = 127;
    pub const exponent_bias: u32 = 127;

    pub fn zero(negative: bool) u32 {
        return if (negative) sign_mask else 0;
    }

    pub fn infinity(negative: bool) u32 {
        return exponent_mask | zero(negative);
    }

    pub fn maxNormal(negative: bool) u32 {
        return (exponent_mask - 1) | zero(negative);
    }

    pub fn defaultNan() u32 {
        return exponent_mask | fraction_top_bit;
    }

    pub fn finite(comptime negative: bool, comptime exponent: i32, comptime significand: u32) u32 {
        if (significand == 0) {
            return zero(negative);
        }

        const highest = @intCast(i32, 31 - @clz(significand));
        const offset = @intCast(i32, stored_fraction_bits) - highest;
        const normalized_exponent = exponent - offset + @intCast(i32, stored_fraction_bits);
        if (offset < 0 or normalized_exponent < exponent_min or normalized_exponent > exponent_max) {
            @compileError("invalid finite value");
        }

        const fraction = (significand << @intCast(u5, offset)) & fraction_mask;
        const biased_exponent = @intCast(u32, normalized_exponent + @intCast(i32, exponent_bias));
        return zero(negative) | fraction | (biased_exponent << stored_fraction_bits);
    }
};

pub const Binary64 = struct {
    pub const total_bits: usize = 64;
    pub const exponent_bits: usize = 11;
    pub const stored_fraction_bits: usize = 52;
    pub const precision_bits: usize = stored_fraction_bits + 1;
    pub const hidden_bit: u64 = @as(u64, 1) << stored_fraction_bits;
    pub const sign_mask: u64 = 0x8000000000000000;
    pub const exponent_mask: u64 = 0x7ff0000000000000;
    pub const fraction_mask: u64 = 0x000fffffffffffff;
    pub const fraction_top_bit: u64 = 0x0008000000000000;
    pub const exponent_min: i32 = -1022;
    pub const exponent_max: i32 = 1023;
    pub const exponent_bias: u64 = 1023;

    pub fn zero(negative: bool) u64 {
        return if (negative) sign_mask else 0;
    }

    pub fn infinity(negative: bool) u64 {
        return exponent_mask | zero(negative);
    }

    pub fn maxNormal(negative: bool) u64 {
        return (exponent_mask - 1) | zero(negative);
    }

    pub fn defaultNan() u64 {
        return exponent_mask | fraction_top_bit;
    }

    pub fn finite(comptime negative: bool, comptime exponent: i32, comptime significand: u64) u64 {
        if (significand == 0) {
            return zero(negative);
        }

        const highest = @intCast(i32, 63 - @clz(significand));
        const offset = @intCast(i32, stored_fraction_bits) - highest;
        const normalized_exponent = exponent - offset + @intCast(i32, stored_fraction_bits);
        if (offset < 0 or normalized_exponent < exponent_min or normalized_exponent > exponent_max) {
            @compileError("invalid finite value");
        }

        const fraction = (significand << @intCast(u6, offset)) & fraction_mask;
        const biased_exponent = @intCast(u64, normalized_exponent + @intCast(i32, exponent_bias));
        return zero(negative) | fraction | (biased_exponent << stored_fraction_bits);
    }
};
