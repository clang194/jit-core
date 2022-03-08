const bits = @import("bits.zig");
const arm_state = @import("arm_state.zig");
const trace = @import("trace.zig");
usingnamespace @import("thumb_fetch_decode.zig");
usingnamespace @import("thumb_shift_math.zig");
usingnamespace @import("thumb_masks_reverse.zig");
usingnamespace @import("thumb_memory_flow.zig");

usingnamespace @import("thumb_trace_alu_flow.zig");
usingnamespace @import("thumb_trace_memory_flow.zig");
usingnamespace @import("thumb_trace_misc_flow.zig");

pub fn buildThumbTrace(word: u16, tape: *trace.Tape) RunError!void {
    return buildThumbTraceAt(word, 0, tape);
}

pub fn buildThumbPacketTraceAt(packet: ThumbWord, pc: u32, tape: *trace.Tape) RunError!void {
    if (packet.size == 2) {
        return buildThumbTraceAt(@intCast(u16, packet.word & 0xffff), pc, tape);
    }
    if (packet.size == 4) {
        return buildThumb32TraceAt(packet.word, pc, tape);
    }
    return error.UnknownInstruction;
}

pub fn buildThumb32TraceAt(word: u32, pc: u32, tape: *trace.Tape) RunError!void {
    if (branchLinkTarget(word, pc)) |target| {
        const link = try tape.literalReg(.lr);
        _ = try tape.storeReg(link, try tape.literalWord((pc + 4) | 1));
        _ = try tape.jump(try tape.literalWord(target));
        return;
    }

    if (try branchLinkExchangeTarget(word, pc)) |target| {
        const link = try tape.literalReg(.lr);
        _ = try tape.storeReg(link, try tape.literalWord((pc + 4) | 1));
        _ = try tape.loadPc(try tape.literalWord(target));
        return;
    }

    return error.UnknownInstruction;
}

pub fn buildThumbTraceAt(word: u16, pc: u32, tape: *trace.Tape) RunError!void {
    if (try traceThumbAluFlow(word, pc, tape)) {
        return;
    }
    if (try traceThumbMemoryFlow(word, pc, tape)) {
        return;
    }
    if (try traceThumbMiscFlow(word, pc, tape)) {
        return;
    }
    return error.UnknownInstruction;
}
