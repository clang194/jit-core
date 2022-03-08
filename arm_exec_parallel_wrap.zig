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

pub fn runUnsignedWrappingMixedHalves(word: u32, state: *arm_state.MachineState, pc: u32, add_sub: bool) ArmStepError!void {
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
    const left_low = left & 0xffff;
    const left_high = (left >> 16) & 0xffff;
    const right_low = right & 0xffff;
    const right_high = (right >> 16) & 0xffff;
    const low_lane = if (add_sub)
        left_low -% right_high
    else
        left_low +% right_high;
    const high_lane = if (add_sub)
        left_high +% right_low
    else
        left_high -% right_low;
    var ge: u32 = 0;
    if (add_sub) {
        if (left_low >= right_high) {
            ge |= 0x3;
        }
        if (left_high + right_low >= 0x10000) {
            ge |= 0xc;
        }
    } else {
        if (left_low + right_high >= 0x10000) {
            ge |= 0x3;
        }
        if (left_high >= right_low) {
            ge |= 0xc;
        }
    }
    state.write(dest, (low_lane & 0xffff) | ((high_lane & 0xffff) << 16));
    state.writeGreaterEqualLanes(ge);
    state.write(.pc, pc + 4);
}

pub fn runSignedWrappingMixedHalves(word: u32, state: *arm_state.MachineState, pc: u32, add_sub: bool) ArmStepError!void {
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
    const left_low = signedHalf(left);
    const left_high = signedHalf(left >> 16);
    const right_low = signedHalf(right);
    const right_high = signedHalf(right >> 16);
    const low_lane = if (add_sub)
        left_low - right_high
    else
        left_low + right_high;
    const high_lane = if (add_sub)
        left_high + right_low
    else
        left_high - right_low;
    const low = if (low_lane < 0) @intCast(u16, low_lane + 65536) else @intCast(u16, low_lane);
    const high = if (high_lane < 0) @intCast(u16, high_lane + 65536) else @intCast(u16, high_lane);
    var ge: u32 = 0;
    if (low_lane >= 0) {
        ge |= 0x3;
    }
    if (high_lane >= 0) {
        ge |= 0xc;
    }
    state.write(dest, @as(u32, low) | (@as(u32, high) << 16));
    state.writeGreaterEqualLanes(ge);
    state.write(.pc, pc + 4);
}

pub fn runUnsignedHalvingSubBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
    var index: u5 = 0;
    while (index < 4) : (index += 1) {
        const shift = @intCast(u5, index * 8);
        const lane = @divFloor(@intCast(i16, (left >> shift) & 0xff) - @intCast(i16, (right >> shift) & 0xff), 2);
        const encoded = if (lane < 0) @intCast(u8, lane + 256) else @intCast(u8, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runUnsignedHalvingSubHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
    var index: u5 = 0;
    while (index < 2) : (index += 1) {
        const shift = @intCast(u5, index * 16);
        const lane = @divFloor(@intCast(i32, (left >> shift) & 0xffff) - @intCast(i32, (right >> shift) & 0xffff), 2);
        const encoded = if (lane < 0) @intCast(u16, lane + 65536) else @intCast(u16, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runSignedHalvingSubBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
    var index: u5 = 0;
    while (index < 4) : (index += 1) {
        const shift = @intCast(u5, index * 8);
        const lane = @divFloor(signedByte(left >> shift) - signedByte(right >> shift), 2);
        const encoded = if (lane < 0) @intCast(u8, lane + 256) else @intCast(u8, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn runSignedHalvingSubHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
    var index: u5 = 0;
    while (index < 2) : (index += 1) {
        const shift = @intCast(u5, index * 16);
        const lane = @divFloor(signedHalf(left >> shift) - signedHalf(right >> shift), 2);
        const encoded = if (lane < 0) @intCast(u16, lane + 65536) else @intCast(u16, lane);
        result |= @as(u32, encoded) << shift;
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

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

pub fn runUnsignedWrappingSubBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        const left_byte = (left >> shift) & 0xff;
        const right_byte = (right >> shift) & 0xff;
        result |= ((left_byte -% right_byte) & 0xff) << shift;
        if (left_byte >= right_byte) {
            ge |= @as(u32, 1) << index;
        }
    }
    state.write(dest, result);
    state.writeGreaterEqualLanes(ge);
    state.write(.pc, pc + 4);
}

pub fn runSignedWrappingSubBytes(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        const lane = signedByte(left >> shift) - signedByte(right >> shift);
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

pub fn runUnsignedWrappingSubHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        const left_half = (left >> shift) & 0xffff;
        const right_half = (right >> shift) & 0xffff;
        result |= ((left_half -% right_half) & 0xffff) << shift;
        if (left_half >= right_half) {
            ge |= @as(u32, 3) << @intCast(u5, index * 2);
        }
    }
    state.write(dest, result);
    state.writeGreaterEqualLanes(ge);
    state.write(.pc, pc + 4);
}

pub fn runSignedWrappingSubHalves(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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
        const lane = signedHalf(left >> shift) - signedHalf(right >> shift);
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

pub fn runByteSelect(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
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

    const mask = byteSelectMask(state.readGreaterEqualLanes());
    const left = state.read(left_reg);
    const right = state.read(right_reg);
    state.write(dest, (left & mask) | (right & ~mask));
    state.write(.pc, pc + 4);
}

pub fn runUnsignedAbsDiffSum(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const dest = armReg(word >> 16);
    const addend = armReg(word >> 12);
    const right_reg = armReg(word >> 8);
    const left_reg = armReg(word);
    const with_addend = (word & 0x0000f000) != 0x0000f000;
    if (dest == .pc or left_reg == .pc or right_reg == .pc or (with_addend and addend == .pc)) {
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
    var index: u5 = 0;
    while (index < 4) : (index += 1) {
        const shift = @intCast(u5, index * 8);
        const left_byte = (left >> shift) & 0xff;
        const right_byte = (right >> shift) & 0xff;
        result += if (left_byte > right_byte) left_byte - right_byte else right_byte - left_byte;
    }
    if (with_addend) {
        result +%= state.read(addend);
    }
    state.write(dest, result);
    state.write(.pc, pc + 4);
}

pub fn byteSelectMask(lanes: u32) u32 {
    var mask: u32 = 0;
    var index: u5 = 0;
    while (index < 4) : (index += 1) {
        if ((lanes & (@as(u32, 1) << index)) != 0) {
            mask |= @as(u32, 0xff) << @intCast(u5, index * 8);
        }
    }
    return mask;
}

pub fn runHalfwordPack(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const base_reg = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const source = armReg(word);
    if (base_reg == .pc or dest == .pc or source == .pc) {
        return error.Unpredictable;
    }

    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const amount = @intCast(u8, (word >> 7) & 0x1f);
    const top = (word & 0x00000040) != 0;
    const shifted = shiftByImmediate(
        state.read(source),
        if (top) ShiftMode.signed_right else ShiftMode.left,
        amount,
        state.carry(),
    ).word;
    const base = state.read(base_reg);
    const result = if (top)
        (base & 0xffff0000) | (shifted & 0x0000ffff)
    else
        (base & 0x0000ffff) | (shifted & 0xffff0000);
    state.write(dest, result);
    state.write(.pc, pc + 4);
}
