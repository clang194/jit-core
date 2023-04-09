const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
usingnamespace @import("thumb_trace_flow.zig");
usingnamespace @import("thumb_run_flow.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");
usingnamespace @import("thumb_memory_flow.zig");

pub const RunError = error{
    UnknownInstruction,
    Unpredictable,
    Full,
    MissingRead,
    MissingWrite,
};

pub const ShiftResult = struct {
    word: u32,
    carry: bool,
};

pub const AddResult = struct {
    word: u32,
    carry: bool,
    overflow: bool,
};

pub const ThumbWord = struct {
    word: u32,
    size: u8,
};

pub fn readThumbWord(hooks: arm_state.HostHooks, pc: u32) RunError!ThumbWord {
    const first_address = pc & 0xfffffffc;
    var first = if (hooks.memory.fetch32) |fetch32| fetch32(first_address) else if (hooks.memory.readDirect32(first_address)) |direct| direct else blk: {
        const read32 = hooks.memory.read32 orelse return error.MissingRead;
        break :blk read32(first_address);
    };
    if ((pc & 2) != 0) {
        first >>= 16;
    }

    const word = @intCast(u16, first & 0xffff);
    if ((word & 0xf800) <= 0xe800) {
        return ThumbWord{ .word = word, .size = 2 };
    }

    const second_pc = pc + 2;
    const second_address = second_pc & 0xfffffffc;
    var second = if (hooks.memory.fetch32) |fetch32| fetch32(second_address) else if (hooks.memory.readDirect32(second_address)) |direct| direct else blk: {
        const read32 = hooks.memory.read32 orelse return error.MissingRead;
        break :blk read32(second_address);
    };
    if ((second_pc & 2) != 0) {
        second >>= 16;
    }

    return ThumbWord{
        .word = @as(u32, word) | ((second & 0xffff) << 16),
        .size = 4,
    };
}

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

pub fn branchLinkTarget(word: u32, pc: u32) ?u32 {
    const first = @intCast(u16, word & 0xffff);
    const second = @intCast(u16, (word >> 16) & 0xffff);
    if ((first & 0xf800) != 0xf000 or (second & 0xf800) != 0xf800) {
        return null;
    }
    return @bitCast(u32, @intCast(i32, pc + 4) + thumb32Offset(word));
}

pub fn branchLinkExchangeTarget(word: u32, pc: u32) RunError!?u32 {
    const first = @intCast(u16, word & 0xffff);
    const second = @intCast(u16, (word >> 16) & 0xffff);
    if ((first & 0xf800) != 0xf000 or (second & 0xf800) != 0xe800) {
        return null;
    }
    if ((second & 1) != 0) {
        return error.Unpredictable;
    }
    return @bitCast(u32, @intCast(i32, alignDown4(pc + 4)) + thumb32Offset(word));
}
