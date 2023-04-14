const a64_state = @import("a64_state.zig");
const a64_vector_access = @import("a64_vector_access.zig");
const setVectorByte = a64_vector_access.setVectorByte;
const vectorByte = a64_vector_access.vectorByte;

pub fn lookupVectorBytes(defaults: a64_state.VectorValue, table: [4]a64_state.VectorValue, table_count: usize, indices: a64_state.VectorValue, total: usize) a64_state.VectorValue {
    var result = if (total == 8) a64_state.VectorValue{ .low = defaults.low, .high = 0 } else defaults;
    var index: usize = 0;
    while (index < total) : (index += 1) {
        const requested = @as(usize, vectorByte(indices, index));
        const group = requested >> 4;
        const offset = requested & 15;
        if (group < table_count) {
            setVectorByte(&result, index, vectorByte(table[group], offset));
        }
    }
    return result;
}
