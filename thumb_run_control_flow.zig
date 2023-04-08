const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");
usingnamespace @import("thumb_memory_flow.zig");

pub fn runThumbControlFlow(word: u16, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!bool {
    if (isStop(word)) {
        return true;
    }

    if (isThumbNoOp(word)) {
        return true;
    }

    if (isThumbBreakpoint(word)) {
        if (hooks.exception) |callback| {
            callback(state.read(.pc), .breakpoint, state, hooks.context);
            return true;
        }
        return error.UnknownInstruction;
    }

    if ((word & 0xff00) == 0xdf00) {
        if (hooks.supervisor) |callback| {
            state.write(.pc, state.read(.pc) + 2);
            callback(@intCast(u32, word & 0xff), state);
            return true;
        }
        if (hooks.fallback) |callback| {
            callback(state.read(.pc), state, hooks.context);
            return true;
        }
        return error.UnknownInstruction;
    }
    return false;
}
