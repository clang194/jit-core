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
