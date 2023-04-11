const arm_state = @import("arm_state.zig");
usingnamespace @import("arm_exec_types.zig");

pub fn runArmBarrier(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if ((word & 0xfffffff0) == 0xf57ff060) {
        if (hooks.instruction_barrier) |callback| {
            callback(hooks.context);
        }
    }
    state.write(.pc, pc + 4);
}

pub fn runArmHint(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks, pc: u32) ArmStepError!void {
    if (hooks.hook_hints) {
        if (hooks.system_hint) |callback| {
            callback(word, armHintKind(word), state, hooks.context);
        }
    }
    state.write(.pc, pc + 4);
}

fn armHintKind(word: u32) arm_state.SystemHint {
    if ((word & 0xfd70f000) == 0xf550f000) {
        return if ((word & 0x00400000) != 0) .preload_data else .preload_data_write;
    }
    if ((word & 0x0fffffff) == 0x0320f004) {
        return .send_event;
    }
    if ((word & 0x0fffffff) == 0x0320f005) {
        return .send_event_local;
    }
    if ((word & 0x0fffffff) == 0x0320f002) {
        return .wait_event;
    }
    if ((word & 0x0fffffff) == 0x0320f003) {
        return .wait_interrupt;
    }
    return .yield_hint;
}
