pub const Core64Methods = struct {
    usingnamespace @import("a64_vector_float_flow.zig").Core64Methods;
    usingnamespace @import("a64_scalar_float_vector_flow.zig").Core64Methods;
    usingnamespace @import("a64_vector_shift_immediate_flow.zig").Core64Methods;
    usingnamespace @import("a64_vector_element_flow.zig").Core64Methods;
    usingnamespace @import("a64_vector_integer_flow.zig").Core64Methods;
    usingnamespace @import("a64_vector_reduce_compare_flow.zig").Core64Methods;
};
