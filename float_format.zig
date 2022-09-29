pub const Binary32 = struct {
    pub const total_bits: usize = 32;
    pub const exponent_bits: usize = 8;
    pub const stored_fraction_bits: usize = 23;
    pub const precision_bits: usize = stored_fraction_bits + 1;
    pub const hidden_bit: u32 = @as(u32, 1) << stored_fraction_bits;
    pub const sign_mask: u32 = 0x80000000;
    pub const exponent_mask: u32 = 0x7f800000;
    pub const fraction_mask: u32 = 0x007fffff;
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
};
