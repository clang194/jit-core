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
usingnamespace @import("arm_exec_types.zig");
usingnamespace @import("arm_exec_fetch_decode.zig");

pub fn runArmDivide(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 12);
    const right = armReg(word >> 8);
    const left = armReg(word);
    if (dest == .pc or right == .pc or left == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (state.conditionHolds(code)) {
        const divisor = state.read(right);
        if (divisor == 0) {
            state.write(dest, 0);
        } else if ((word & 0x00200000) != 0) {
            state.write(dest, @divTrunc(state.read(left), divisor));
        } else {
            const signed_divisor = @bitCast(i32, divisor);
            const signed_left = @bitCast(i32, state.read(left));
            const result = if (signed_left == @as(i32, -2147483648) and signed_divisor == -1)
                signed_left
            else
                @divTrunc(signed_left, signed_divisor);
            state.write(dest, @bitCast(u32, result));
        }
    }
    state.write(.pc, pc + 4);
}
