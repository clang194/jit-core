const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");

pub fn isStop(word: u16) bool {
    return (word & 0xff00) == 0xde00;
}

pub fn isThumbBreakpoint(word: u16) bool {
    return (word & 0xff00) == 0xbe00;
}

pub fn isThumbNoOp(word: u16) bool {
    return word == 0xbf00;
}

pub fn thumbSystemHint(word: u16) ?arm_state.SystemHint {
    return switch (word) {
        0xbf40 => .send_event,
        0xbf50 => .send_event_local,
        0xbf20 => .wait_event,
        0xbf30 => .wait_interrupt,
        0xbf10 => .yield_hint,
        else => null,
    };
}

pub fn isCompareZeroBranch(word: u16) bool {
    return (word & 0xf500) == 0xb100;
}

pub fn compareZeroBranchTarget(word: u16, pc: u32) u32 {
    const high = @as(u32, (word >> 9) & 1) << 6;
    const low = @as(u32, (word >> 3) & 0x1f) << 1;
    return pc + 4 + high + low;
}

pub fn branchTarget(word: u16, pc: u32) ?u32 {
    if ((word & 0xf800) != 0xe000) {
        return null;
    }
    const imm = @as(u32, word & 0x07ff) << 1;
    const offset = bits.signExtend32(imm, 12);
    return @intCast(u32, @intCast(i32, pc + 4) + offset);
}
