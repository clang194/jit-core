const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");
usingnamespace @import("thumb_memory_flow.zig");

usingnamespace @import("thumb_run_control_flow.zig");
usingnamespace @import("thumb_run_alu_flow.zig");
usingnamespace @import("thumb_run_memory_access_flow.zig");
usingnamespace @import("thumb_run_stack_branch_flow.zig");

pub fn runThumb(word: u16, state: *arm_state.MachineState) RunError!void {
    return runThumbWithHooks(word, state, arm_state.HostHooks.empty());
}

pub fn runThumbPacketWithHooks(packet: ThumbWord, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!void {
    if (packet.size == 2) {
        return runThumbWithHooks(@intCast(u16, packet.word & 0xffff), state, hooks);
    }
    if (packet.size == 4) {
        return runThumb32WithHooks(packet.word, state, hooks);
    }
    return error.UnknownInstruction;
}

pub fn runThumb32WithHooks(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!void {
    _ = hooks;
    const pc = state.read(.pc);
    if (branchLinkTarget(word, pc)) |target| {
        state.write(.lr, (pc + 4) | 1);
        state.write(.pc, target);
        return;
    }
    if (try branchLinkExchangeTarget(word, pc)) |target| {
        state.write(.lr, (pc + 4) | 1);
        state.setThumb(false);
        state.write(.pc, target);
        return;
    }
    return error.UnknownInstruction;
}


pub fn runThumbWithHooks(word: u16, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!void {
    if (try runThumbControlFlow(word, state, hooks)) {
        return;
    }
    if (try runThumbAluFlow(word, state, hooks)) {
        return;
    }
    if (try runThumbMemoryAccessFlow(word, state, hooks)) {
        return;
    }
    if (try runThumbStackBranchFlow(word, state, hooks)) {
        return;
    }
    return error.UnknownInstruction;
}
