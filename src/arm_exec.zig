const arm_state = @import("arm_state.zig");

pub const ArmStepError = error{
    UnknownInstruction,
    MissingRead,
};

pub fn readArmWord(hooks: arm_state.HostHooks, pc: u32) ArmStepError!u32 {
    if (hooks.read32 == null) {
        return error.MissingRead;
    }
    return hooks.read32.?(pc & 0xfffffffc);
}

pub fn runArmWord(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks) ArmStepError!void {
    _ = word;
    const pc = state.read(.pc);
    if (hooks.fallback) |callback| {
        callback(pc, state);
        return;
    }
    return error.UnknownInstruction;
}

pub fn runArmWithHooks(state: *arm_state.MachineState, hooks: arm_state.HostHooks) ArmStepError!void {
    const pc = state.read(.pc);
    const word = readArmWord(hooks, pc) catch |err| switch (err) {
        error.MissingRead => {
            if (hooks.fallback) |callback| {
                callback(pc, state);
                return;
            }
            return err;
        },
        else => return err,
    };
    return runArmWord(word, state, hooks);
}
