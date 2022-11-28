const a64_state = @import("a64_state.zig");
usingnamespace @import("a64_immediate_vectors.zig");
usingnamespace @import("a64_vector_access.zig");

fn dotTerm(left: u64, right: u64, signed: bool) u64 {
    if (signed) {
        const left_value = @bitCast(i64, signExtendRuntime(left, 8));
        const right_value = @bitCast(i64, signExtendRuntime(right, 8));
        return @bitCast(u64, left_value *% right_value);
    }
    return left *% right;
}

pub fn accumulateByteDots(target: a64_state.VectorValue, left: a64_state.VectorValue, right: a64_state.VectorValue, full: bool, signed: bool) a64_state.VectorValue {
    const lanes = if (full) @as(usize, 4) else @as(usize, 2);
    var result = if (full) target else a64_state.VectorValue{ .low = target.low, .high = 0 };
    var lane: usize = 0;
    while (lane < lanes) : (lane += 1) {
        var total: u64 = 0;
        var part: usize = 0;
        while (part < 4) : (part += 1) {
            const index = lane * 4 + part;
            total +%= dotTerm(vectorElement(left, index, 1), vectorElement(right, index, 1), signed);
        }
        const prior = vectorElement(result, lane, 4);
        setVectorElement(&result, lane, 4, prior +% total);
    }
    return result;
}

pub fn accumulateByteDotsWithLane(target: a64_state.VectorValue, left: a64_state.VectorValue, right: a64_state.VectorValue, full: bool, lane_index: usize, signed: bool) a64_state.VectorValue {
    const lanes = if (full) @as(usize, 4) else @as(usize, 2);
    var result = if (full) target else a64_state.VectorValue{ .low = target.low, .high = 0 };
    var lane: usize = 0;
    while (lane < lanes) : (lane += 1) {
        var total: u64 = 0;
        var part: usize = 0;
        while (part < 4) : (part += 1) {
            total +%= dotTerm(vectorElement(left, lane * 4 + part, 1), vectorElement(right, lane_index * 4 + part, 1), signed);
        }
        const prior = vectorElement(result, lane, 4);
        setVectorElement(&result, lane, 4, prior +% total);
    }
    return result;
}
