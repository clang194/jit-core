const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
const thumb_decode = @import("thumb_fetch_decode.zig");
const RunError = thumb_decode.RunError;
const compareZeroBranchTarget = thumb_decode.compareZeroBranchTarget;
const isCompareZeroBranch = thumb_decode.isCompareZeroBranch;
const isStop = thumb_decode.isStop;
const isThumbBreakpoint = thumb_decode.isThumbBreakpoint;
const isThumbNoOp = thumb_decode.isThumbNoOp;
const thumbSystemHint = thumb_decode.thumbSystemHint;
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");
usingnamespace @import("thumb_memory_flow.zig");

pub fn runThumbControlFlow(word: u16, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!bool {
    if (isStop(word)) {
        if (hooks.exception) |callback| {
            callback(state.read(.pc), .undefined_instruction, state, hooks.context);
            return true;
        }
        return error.UndefinedInstruction;
    }

    if (isThumbNoOp(word)) {
        return true;
    }

    if (thumbSystemHint(word)) |kind| {
        if (hooks.hook_hints) {
            if (hooks.system_hint) |callback| {
                callback(word, kind, state, hooks.context);
            }
        }
        state.write(.pc, state.read(.pc) + 2);
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

    if (isCompareZeroBranch(word)) {
        const source = arm_state.lowReg(word);
        const nonzero = (word & 0x0800) != 0;
        const read = state.read(source);
        const taken = if (nonzero) read != 0 else read == 0;
        state.write(.pc, if (taken) compareZeroBranchTarget(word, state.read(.pc)) else state.read(.pc) + 2);
        return true;
    }

    return false;
}
