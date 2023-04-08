const arm_state = @import("arm_state.zig");
const crc = @import("a64_divide_crc.zig");
usingnamespace @import("arm_exec_types.zig");
usingnamespace @import("arm_exec_fetch_decode.zig");

pub fn runArmCrc(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    const acc = armReg(word >> 16);
    const data_reg = armReg(word);
    const size = @intCast(u2, (word >> 21) & 3);
    const code = armCondition(word) orelse return error.UnknownInstruction;
    if (dest == .pc or acc == .pc or data_reg == .pc or size == 3 or code != .al) {
        return error.Unpredictable;
    }

    if (state.conditionHolds(code)) {
        const bytes = crcByteCount(size);
        const data = state.read(data_reg);
        const start = state.read(acc);
        const result = if (isArmCrcAlt(word))
            crc.crc32c(start, data, bytes)
        else
            crc.crc32(start, data, bytes);
        state.write(dest, result);
    }
    state.write(.pc, pc + 4);
}

fn crcByteCount(size: u2) u4 {
    return switch (size) {
        0 => 1,
        1 => 2,
        2 => 4,
        3 => 4,
    };
}
