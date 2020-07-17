const arm_state = @import("arm_state.zig");

pub const ArmStepError = error{
    UnknownInstruction,
    Unpredictable,
    MissingRead,
};

pub const AddResult = struct {
    word: u32,
    carry: bool,
    overflow: bool,
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

pub fn isAdcImmediate(word: u32) bool {
    return (word & 0x0fe00000) == 0x02a00000 and armCondition(word) != null;
}

pub fn expandArmImmediate(rotate: u8, value: u8) u32 {
    return rotateRightWord(@as(u32, value), rotate * 2);
}

pub fn runArmWord(word: u32, state: *arm_state.MachineState, hooks: arm_state.HostHooks) ArmStepError!void {
    const pc = state.read(.pc);
    if (isAdcImmediate(word)) {
        return runAdcImmediate(word, state, pc);
    }

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

fn runAdcImmediate(word: u32, state: *arm_state.MachineState, pc: u32) ArmStepError!void {
    const code = armCondition(word).?;
    if (!state.conditionHolds(code)) {
        state.write(.pc, pc + 4);
        return;
    }

    const set_flags = ((word >> 20) & 1) != 0;
    const base = armReg(word >> 16);
    const dest = armReg(word >> 12);
    const rotate = @intCast(u8, (word >> 8) & 0xf);
    const imm = @intCast(u8, word & 0xff);
    const amount = expandArmImmediate(rotate, imm);
    const result = addWithCarry(readArmOperand(state, base, pc), amount, state.carry());

    if (dest == .pc) {
        if (set_flags) {
            return error.Unpredictable;
        }
        writeArmAluPc(state, result.word);
        return;
    }

    state.write(dest, result.word);
    if (set_flags) {
        state.setNegative((result.word & 0x80000000) != 0);
        state.setZero(result.word == 0);
        state.setCarry(result.carry);
        state.setOverflow(result.overflow);
    }
    state.write(.pc, pc + 4);
}

fn armReg(value: u32) arm_state.ArmReg {
    return @intToEnum(arm_state.ArmReg, @intCast(u8, value & 0xf));
}

fn readArmOperand(state: *const arm_state.MachineState, reg: arm_state.ArmReg, pc: u32) u32 {
    if (reg == .pc) {
        return pc + 8;
    }
    return state.read(reg);
}

fn writeArmAluPc(state: *arm_state.MachineState, value: u32) void {
    state.write(.pc, value & 0xfffffffc);
}

fn rotateRightWord(value: u32, amount: u8) u32 {
    const shift = amount & 31;
    if (shift == 0) {
        return value;
    }
    return (value >> @intCast(u5, shift)) | (value << @intCast(u5, 32 - shift));
}

fn addWithCarry(left: u32, right: u32, carry_in: bool) AddResult {
    const carry: u64 = if (carry_in) 1 else 0;
    const wide = @as(u64, left) + @as(u64, right) + carry;
    const result = @intCast(u32, wide & 0xffffffff);
    const overflow = ((~(left ^ right) & (left ^ result)) & 0x80000000) != 0;
    return AddResult{
        .word = result,
        .carry = wide > 0xffffffff,
        .overflow = overflow,
    };
}
