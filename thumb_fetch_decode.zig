const arm_state = @import("arm_state.zig");
const short_decode = @import("thumb_short_decode.zig");
const wide_decode = @import("thumb_wide_decode.zig");
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

pub const isStop = short_decode.isStop;
pub const isThumbBreakpoint = short_decode.isThumbBreakpoint;
pub const isThumbNoOp = short_decode.isThumbNoOp;
pub const thumbSystemHint = short_decode.thumbSystemHint;
pub const isCompareZeroBranch = short_decode.isCompareZeroBranch;
pub const compareZeroBranchTarget = short_decode.compareZeroBranchTarget;
pub const branchTarget = short_decode.branchTarget;
pub const branchLinkTarget = wide_decode.branchLinkTarget;
pub const branchLinkExchangeTarget = wide_decode.branchLinkExchangeTarget;
