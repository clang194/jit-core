pub const ShiftResidue = enum {
    zero,
    below_half,
    half,
    above_half,
};

pub fn classifyRightShiftResidue32(value: u32, amount: i32) ShiftResidue {
    if (amount <= 0 or value == 0) {
        return .zero;
    }
    if (amount > 32) {
        return if ((value & 0x80000000) != 0) .above_half else .below_half;
    }
    const half = @as(u32, 1) << @intCast(u5, amount - 1);
    const mask = if (amount == 32) ~@as(u32, 0) else (@as(u32, 1) << @intCast(u5, amount)) - 1;
    const residue = value & mask;
    if (residue == 0) {
        return .zero;
    }
    if (residue < half) {
        return .below_half;
    }
    if (residue == half) {
        return .half;
    }
    return .above_half;
}

pub fn classifyRightShiftResidue64(value: u64, amount: i32) ShiftResidue {
    if (amount <= 0 or value == 0) {
        return .zero;
    }
    if (amount > 64) {
        return if ((value & 0x8000000000000000) != 0) .above_half else .below_half;
    }
    const half = @as(u64, 1) << @intCast(u6, amount - 1);
    const mask = if (amount == 64) ~@as(u64, 0) else (@as(u64, 1) << @intCast(u6, amount)) - 1;
    const residue = value & mask;
    if (residue == 0) {
        return .zero;
    }
    if (residue < half) {
        return .below_half;
    }
    if (residue == half) {
        return .half;
    }
    return .above_half;
}
