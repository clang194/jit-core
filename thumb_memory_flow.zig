const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
const thumb_decode = @import("thumb_fetch_decode.zig");
const RunError = thumb_decode.RunError;
const thumb_reverse = @import("thumb_masks_reverse.zig");
const byteReverseHalf = thumb_reverse.byteReverseHalf;
const byteReverseWord = thumb_reverse.byteReverseWord;
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");

pub fn readMemory16(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32) RunError!u16 {
    var value = if (hooks.memory.readDirect16(address)) |direct| direct else blk: {
        const read16 = hooks.memory.read16 orelse return error.MissingRead;
        break :blk read16(address);
    };
    if (state.bigEndian()) {
        value = @intCast(u16, byteReverseHalf(value));
    }
    return value;
}

pub fn readMemory32(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32) RunError!u32 {
    var value = if (hooks.memory.readDirect32(address)) |direct| direct else blk: {
        const read32 = hooks.memory.read32 orelse return error.MissingRead;
        break :blk read32(address);
    };
    if (state.bigEndian()) {
        value = byteReverseWord(value);
    }
    return value;
}

pub fn writeMemory16(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32, value: u16) RunError!void {
    var data = value;
    if (state.bigEndian()) {
        data = @intCast(u16, byteReverseHalf(data));
    }
    if (hooks.memory.writeDirect16(address, data)) {
        return;
    }
    const write16 = hooks.memory.write16 orelse return error.MissingWrite;
    write16(address, data);
}

pub fn writeMemory32(state: *const arm_state.MachineState, hooks: arm_state.HostHooks, address: u32, value: u32) RunError!void {
    var data = value;
    if (state.bigEndian()) {
        data = byteReverseWord(data);
    }
    if (hooks.memory.writeDirect32(address, data)) {
        return;
    }
    const write32 = hooks.memory.write32 orelse return error.MissingWrite;
    write32(address, data);
}

pub fn readOperand(state: *const arm_state.MachineState, reg: arm_state.ArmReg, pc: u32) u32 {
    if (reg == .pc) {
        return pc + 4;
    }
    return state.read(reg);
}

pub fn traceOperand(tape: *trace.Tape, reg: arm_state.ArmReg, pc: u32) RunError!usize {
    if (reg == .pc) {
        return tape.literalWord(pc + 4);
    }
    const stored_reg = try tape.literalReg(reg);
    return tape.loadReg(stored_reg);
}

pub fn alignDown4(value: u32) u32 {
    return value & 0xfffffffc;
}

pub fn thumb32Offset(word: u32) i32 {
    const first = word & 0x07ff;
    const second = (word >> 16) & 0x07ff;
    return bits.signExtend32((first << 12) | (second << 1), 23);
}

pub fn thumbPcWrite(value: u32) u32 {
    return value & 0xfffffffe;
}

pub fn loadWritePc(state: *arm_state.MachineState, value: u32) void {
    if ((value & 1) != 0) {
        state.setThumb(true);
        state.write(.pc, value & 0xfffffffe);
    } else {
        state.setThumb(false);
        state.write(.pc, value & 0xfffffffc);
    }
}

pub fn updateNz(state: *arm_state.MachineState, value: u32) void {
    state.setNegative(bits.topBit(value));
    state.setZero(bits.isZero(value));
}
