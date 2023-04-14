const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
const thumb_decode = @import("thumb_fetch_decode.zig");
const RunError = thumb_decode.RunError;
const thumb_memory = @import("thumb_memory_flow.zig");
const alignDown4 = thumb_memory.alignDown4;
const readMemory16 = thumb_memory.readMemory16;
const readMemory32 = thumb_memory.readMemory32;
const writeMemory16 = thumb_memory.writeMemory16;
const writeMemory32 = thumb_memory.writeMemory32;
const thumb_reverse = @import("thumb_masks_reverse.zig");
const signExtendByte = thumb_reverse.signExtendByte;
const signExtendHalf = thumb_reverse.signExtendHalf;
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");
usingnamespace @import("thumb_memory_flow.zig");

pub fn runThumbMemoryAccessFlow(word: u16, state: *arm_state.MachineState, hooks: arm_state.HostHooks) RunError!bool {
    if ((word & 0xf800) == 0x4800) {
        const dest = arm_state.lowReg(word >> 8);
        const pc = state.read(.pc);
        const address = alignDown4(pc + 4) + (@as(u32, word & 0xff) << 2);
        state.write(dest, try readMemory32(state, hooks, address));
        return true;
    }

    if ((word & 0xfe00) == 0x5000) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const data = arm_state.lowReg(word);
        try writeMemory32(state, hooks, state.read(base) + state.read(source), state.read(data));
        return true;
    }

    if ((word & 0xfe00) == 0x5200) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const data = arm_state.lowReg(word);
        try writeMemory16(state, hooks, state.read(base) + state.read(source), @intCast(u16, state.read(data) & 0xffff));
        return true;
    }

    if ((word & 0xfe00) == 0x5400) {
        const write8 = hooks.memory.write8 orelse return error.MissingWrite;
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const data = arm_state.lowReg(word);
        write8(state.read(base) + state.read(source), bits.lowByte(state.read(data)));
        return true;
    }

    if ((word & 0xfe00) == 0x5600) {
        const read8 = hooks.memory.read8 orelse return error.MissingRead;
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendByte(read8(state.read(base) + state.read(source))));
        return true;
    }

    if ((word & 0xfe00) == 0x5800) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, try readMemory32(state, hooks, state.read(base) + state.read(source)));
        return true;
    }

    if ((word & 0xfe00) == 0x5a00) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, try readMemory16(state, hooks, state.read(base) + state.read(source)));
        return true;
    }

    if ((word & 0xfe00) == 0x5c00) {
        const read8 = hooks.memory.read8 orelse return error.MissingRead;
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, read8(state.read(base) + state.read(source)));
        return true;
    }

    if ((word & 0xfe00) == 0x5e00) {
        const source = arm_state.lowReg(word >> 6);
        const base = arm_state.lowReg(word >> 3);
        const dest = arm_state.lowReg(word);
        state.write(dest, signExtendHalf(try readMemory16(state, hooks, state.read(base) + state.read(source))));
        return true;
    }

    if ((word & 0xf800) == 0x6000) {
        const data = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f) << 2;
        try writeMemory32(state, hooks, state.read(base) + offset, state.read(data));
        return true;
    }

    if ((word & 0xf800) == 0x6800) {
        const dest = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f) << 2;
        state.write(dest, try readMemory32(state, hooks, state.read(base) + offset));
        return true;
    }

    if ((word & 0xf800) == 0x7000) {
        const write8 = hooks.memory.write8 orelse return error.MissingWrite;
        const data = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f);
        write8(state.read(base) + offset, bits.lowByte(state.read(data)));
        return true;
    }

    if ((word & 0xf800) == 0x7800) {
        const read8 = hooks.memory.read8 orelse return error.MissingRead;
        const dest = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f);
        state.write(dest, read8(state.read(base) + offset));
        return true;
    }

    if ((word & 0xf800) == 0x8000) {
        const data = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f) << 1;
        try writeMemory16(state, hooks, state.read(base) + offset, @intCast(u16, state.read(data) & 0xffff));
        return true;
    }

    if ((word & 0xf800) == 0x8800) {
        const dest = arm_state.lowReg(word);
        const base = arm_state.lowReg(word >> 3);
        const offset = @as(u32, (word >> 6) & 0x1f) << 1;
        state.write(dest, try readMemory16(state, hooks, state.read(base) + offset));
        return true;
    }

    if ((word & 0xf800) == 0x9000) {
        const data = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        try writeMemory32(state, hooks, state.read(.sp) + offset, state.read(data));
        return true;
    }

    if ((word & 0xf800) == 0x9800) {
        const dest = arm_state.lowReg(word >> 8);
        const offset = @as(u32, word & 0xff) << 2;
        state.write(dest, try readMemory32(state, hooks, state.read(.sp) + offset));
        return true;
    }
    return false;
}
