const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const FloatNanMode64 = main.FloatNanMode64;

pub fn logicalOp(wide: bool, opcode: u2, left: u64, right: u64, invert: bool) u64 {
    const operand = if (invert) ~right else right;
    const result = switch (opcode) {
        0, 3 => left & operand,
        1 => left | operand,
        else => left ^ operand,
    };
    if (wide) {
        return result;
    }
    return @as(u64, @intCast(u32, result));
}

pub fn decodeLogicalMask(n: bool, imms: u6, immr: u6) ?u64 {
    const decoded = decodeBitPattern(n, imms, immr, true) orelse return null;
    return decoded.write;
}

pub const BitPattern = struct {
    write: u64,
    limit: u64,
};

pub fn decodeBitPattern(n: bool, imms: u6, immr: u6, reject_full: bool) ?BitPattern {
    const marker = (if (n) @as(u64, 1) << 6 else @as(u64, 0)) | @as(u64, imms ^ 0x3f);
    const len = highestSetBit(marker);
    if (len < 1) {
        return null;
    }

    const levels = ones(@intCast(u8, len));
    if (reject_full and (@as(u64, imms) & levels) == levels) {
        return null;
    }

    const s = @as(u64, imms) & levels;
    const r = @as(u64, immr) & levels;
    const d = (s -% r) & levels;
    const size = @as(u6, 1) << @intCast(u3, len);
    const write = bits.rotateRight64(replicate64(ones(@intCast(u8, s + 1)), size), @intCast(u6, r));
    const limit = replicate64(ones(@intCast(u8, d + 1)), size);
    return BitPattern{
        .write = write,
        .limit = limit,
    };
}

pub fn highestSetBit(value: u64) i8 {
    var remaining = value;
    var result: i8 = -1;
    while (remaining != 0) {
        remaining >>= 1;
        result += 1;
    }
    return result;
}

pub fn ones(count: u8) u64 {
    if (count >= 64) {
        return ~@as(u64, 0);
    }
    return (@as(u64, 1) << @intCast(u6, count)) - 1;
}

pub fn replicate64(value: u64, element_size: u6) u64 {
    var result = value & ones(element_size);
    var size = element_size;
    while (size < 64) {
        result |= result << size;
        size *= 2;
    }
    return result;
}
