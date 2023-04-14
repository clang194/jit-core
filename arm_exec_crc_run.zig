const arm_state = @import("arm_state.zig");
const arm_coprocessor = @import("arm_exec_coprocessor.zig");
const armCondition = arm_coprocessor.armCondition;
const runExternalArmHandler = arm_coprocessor.runExternalArmHandler;
const arm_registers = @import("arm_exec_register_memory.zig");
const armReg = arm_registers.armReg;
const loadWritePc = arm_registers.loadWritePc;
const nextArmReg = arm_registers.nextArmReg;
const readArmOperand = arm_registers.readArmOperand;
const arm_types = @import("arm_exec_types.zig");
const ArmStepError = arm_types.ArmStepError;
const AddResult = arm_types.AddResult;
const CoprocessorOp = arm_types.CoprocessorOp;
const DataOp = arm_types.DataOp;
const DualMultiplyOp = arm_types.DualMultiplyOp;
const ExtendOp = arm_types.ExtendOp;
const FloatBinaryOp = arm_types.FloatBinaryOp;
const FloatUnaryOp = arm_types.FloatUnaryOp;
const FloatVectorPlan = arm_types.FloatVectorPlan;
const HalfMultiplyOp = arm_types.HalfMultiplyOp;
const MultiplyOp = arm_types.MultiplyOp;
const SaturatingWordResult = arm_types.SaturatingWordResult;
const ShiftMode = arm_types.ShiftMode;
const ShiftResult = arm_types.ShiftResult;
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
