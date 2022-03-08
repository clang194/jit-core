const arm_state = @import("arm_state.zig");
const bits = @import("bits.zig");
usingnamespace @import("arm_exec_types.zig");
usingnamespace @import("arm_exec_fetch_decode.zig");
usingnamespace @import("arm_exec_dispatch.zig");
usingnamespace @import("arm_exec_coprocessor.zig");
usingnamespace @import("arm_exec_float_decode.zig");
usingnamespace @import("arm_exec_float_run.zig");
usingnamespace @import("arm_exec_multiply_run.zig");
usingnamespace @import("arm_exec_float_math.zig");
usingnamespace @import("arm_exec_status_branch.zig");
usingnamespace @import("arm_exec_data_transfer.zig");
usingnamespace @import("arm_exec_saturate_scalar.zig");
usingnamespace @import("arm_exec_parallel_saturate.zig");
usingnamespace @import("arm_exec_parallel_halve.zig");
usingnamespace @import("arm_exec_memory_run.zig");
usingnamespace @import("arm_exec_transfer_checks.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
usingnamespace @import("arm_exec_immediate_run.zig");
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");

pub fn runUnsignedWrappingAddBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    var result: u32 = 0;
    var ge: u32 = 0;
    var index: u5 = 0;
    while (index < 4) : (index += 1) {
        const shift = @intCast(u5, index * 8);
        const sum = ((left >> shift) & 0xff) + ((right >> shift) & 0xff);
        result |= (sum & 0xff) << shift;
        if (sum >= 0x100) {
            ge |= @as(u32, 1) << index;
        }
    }
    state.write(dest, result);
    state.writeGreaterEqualLanes(ge);
    state.write(.pc, pc + 4);
}

pub fn runSignedWrappingAddBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    var result: u32 = 0;
    var ge: u32 = 0;
    var index: u5 = 0;
    while (index < 4) : (index += 1) {
        const shift = @intCast(u5, index * 8);
        const lane = signedByte(left >> shift) + signedByte(right >> shift);
        const encoded = if (lane < 0) @intCast(u8, lane + 256) else @intCast(u8, lane);
        result |= @as(u32, encoded) << shift;
        if (lane >= 0) {
            ge |= @as(u32, 1) << index;
        }
    }
    state.write(dest, result);
    state.writeGreaterEqualLanes(ge);
    state.write(.pc, pc + 4);
}

pub fn runUnsignedWrappingAddHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    var result: u32 = 0;
    var ge: u32 = 0;
    var index: u5 = 0;
    while (index < 2) : (index += 1) {
        const shift = @intCast(u5, index * 16);
        const sum = ((left >> shift) & 0xffff) + ((right >> shift) & 0xffff);
        result |= (sum & 0xffff) << shift;
        if (sum >= 0x10000) {
            ge |= @as(u32, 3) << @intCast(u5, index * 2);
        }
    }
    state.write(dest, result);
    state.writeGreaterEqualLanes(ge);
    state.write(.pc, pc + 4);
}

pub fn runSignedWrappingAddHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const left_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const right_reg = armReg(word);
    if (left_reg == .pc or dest == .pc or right_reg == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const left = state.read(left_reg);
    const right = state.read(right_reg);
    var result: u32 = 0;
    var ge: u32 = 0;
    var index: u5 = 0;
    while (index < 2) : (index += 1) {
        const shift = @intCast(u5, index * 16);
        const lane = signedHalf(left >> shift) + signedHalf(right >> shift);
        const encoded = if (lane < 0) @intCast(u16, lane + 65536) else @intCast(u16, lane);
        result |= @as(u32, encoded) << shift;
        if (lane >= 0) {
            ge |= @as(u32, 3) << @intCast(u5, index * 2);
        }
    }
    state.write(dest, result);
    state.writeGreaterEqualLanes(ge);
    state.write(.pc, pc + 4);
}
