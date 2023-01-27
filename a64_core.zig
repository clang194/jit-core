const a64_state = @import("a64_state.zig");
const a64_reservation = @import("a64_reservation.zig");
const bits = @import("bits.zig");

pub const Core64Error = error{
    Busy,
    UnallocatedEncoding,
    ReservedInstruction,
    Unpredictable,
    MissingRead,
    MissingWrite,
    MissingFallback,
};

pub const FaultKind64 = enum {
    unallocated_encoding,
    reserved_value,
    unpredictable_instruction,
    yield_hint,
    wait_for_event,
    wait_for_interrupt,
    send_event,
    send_event_local,
    breakpoint,
};

pub const CacheAction64 = enum {
    clean_invalidate_set_way,
    clean_invalidate_address,
    clean_set_way,
    clean_address_inner,
    clean_address_unified,
    clean_address_persistent,
    invalidate_set_way,
    invalidate_address,
    zero_address,
};

pub const FloatNanMode64 = enum {
    accurate,
    force_default,
    unchecked,
};

pub const MemoryHooks64 = struct {
    readCode: ?fn (u64, ?*anyopaque) u32,
    read8: ?fn (u64, ?*anyopaque) u8,
    read16: ?fn (u64, ?*anyopaque) u16,
    read32: ?fn (u64, ?*anyopaque) u32,
    read64: ?fn (u64, ?*anyopaque) u64,
    read128: ?fn (u64, ?*anyopaque) a64_state.VectorValue,
    write8: ?fn (u64, u8, ?*anyopaque) void,
    write16: ?fn (u64, u16, ?*anyopaque) void,
    write32: ?fn (u64, u32, ?*anyopaque) void,
    write64: ?fn (u64, u64, ?*anyopaque) void,
    write128: ?fn (u64, a64_state.VectorValue, ?*anyopaque) void,
    readOnly: ?fn (u64, ?*anyopaque) bool,
    direct: ?fn (u64, usize, ?*anyopaque) ?[*]u8,

    pub fn empty() MemoryHooks64 {
        return MemoryHooks64{
            .readCode = null,
            .read8 = null,
            .read16 = null,
            .read32 = null,
            .read64 = null,
            .read128 = null,
            .write8 = null,
            .write16 = null,
            .write32 = null,
            .write64 = null,
            .write128 = null,
            .readOnly = null,
            .direct = null,
        };
    }
};

pub const HostHooks64 = struct {
    pub const CycleHooks = struct {
        add: ?fn (u64, ?*anyopaque) void,
        remaining: ?fn (?*anyopaque) u64,

        pub fn empty() CycleHooks {
            return CycleHooks{
                .add = null,
                .remaining = null,
            };
        }
    };

    memory: MemoryHooks64,
    fallback: ?fn (u64, usize, *a64_state.MachineState64, ?*anyopaque) void,
    supervisor: ?fn (u32, *a64_state.MachineState64, ?*anyopaque) void,
    exception: ?fn (u64, FaultKind64, ?*anyopaque) void,
    cache: ?fn (CacheAction64, u64, ?*anyopaque) void,
    instruction_barrier: ?fn (?*anyopaque) void,
    resolve_unpredictable_cases: bool,
    cache_type_value: u32,
    counter_frequency_value: u32,
    zero_cache_block_words_log2: u4,
    thread_value: ?*u64,
    read_only_thread_value: ?*const u64,
    worker_index: usize,
    shared_reservations: ?*a64_reservation.ReservationTable64,
    float_nan_mode: FloatNanMode64,
    cycles: CycleHooks,
    counter_value: ?fn (?*anyopaque) u64,
    context: ?*anyopaque,

    pub fn empty() HostHooks64 {
        return HostHooks64{
            .memory = MemoryHooks64.empty(),
            .fallback = null,
            .supervisor = null,
            .exception = null,
            .cache = null,
            .instruction_barrier = null,
            .resolve_unpredictable_cases = false,
            .cache_type_value = 0x8444c004,
            .counter_frequency_value = 600000000,
            .zero_cache_block_words_log2 = 4,
            .thread_value = null,
            .read_only_thread_value = null,
            .worker_index = 0,
            .shared_reservations = null,
            .float_nan_mode = .accurate,
            .cycles = CycleHooks.empty(),
            .counter_value = null,
            .context = null,
        };
    }
};

pub const Core64 = struct {
    state: a64_state.MachineState64,
    hooks: HostHooks64,
    active: bool,
    halt: bool,

    usingnamespace @import("a64_lifecycle.zig").Core64Methods;
    usingnamespace @import("a64_dispatch.zig").Core64Methods;
    usingnamespace @import("a64_frontend_flow.zig").Core64Methods;
    usingnamespace @import("a64_memory_flow.zig").Core64Methods;
    usingnamespace @import("a64_integer_flow.zig").Core64Methods;
    usingnamespace @import("a64_float_flow.zig").Core64Methods;
    usingnamespace @import("a64_vector_transfer_flow.zig").Core64Methods;
    usingnamespace @import("a64_vector_lane_flow.zig").Core64Methods;
    usingnamespace @import("a64_vector_math_flow.zig").Core64Methods;
    usingnamespace @import("a64_system_flow.zig").Core64Methods;
    usingnamespace @import("a64_state_flow.zig").Core64Methods;
};
