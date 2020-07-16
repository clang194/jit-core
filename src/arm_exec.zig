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

pub fn isSupervisorCall(word: u32) bool {
    return (word & 0x0f000000) == 0x0f000000 and armCondition(word) != null;
}

pub fn supervisorImmediate(word: u32) u32 {
    return word & 0x00ffffff;
}

pub fn runArmWord(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks) ArmStepError!void {
    const pc = state.read(.pc);
    if (isSupervisorCall(word)) {
        const code = armCondition(word).?;
        if (!state.conditionHolds(code)) {
            state.write(.pc, pc + 4);
            return;
        }
        if (hooks.supervisor) |callback| {
            callback(supervisorImmediate(word), state);
            if (state.read(.pc) == pc) {
                state.write(.pc, pc + 4);
            }
            return;
        }
    }

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

fn armCondition(word: u32) ?arm_state.ConditionCode {
    return arm_state.conditionFromNibble(@intCast(u4, word >> 28));
}
