const arm_state = @import("arm_state.zig");
const bits = @import("bits.zig");
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
usingnamespace @import("arm_exec_parallel_wrap.zig");
usingnamespace @import("arm_exec_memory_run.zig");
usingnamespace @import("arm_exec_transfer_checks.zig");
usingnamespace @import("arm_exec_alu_helpers.zig");
usingnamespace @import("arm_exec_immediate_run.zig");
usingnamespace @import("arm_exec_register_memory.zig");
usingnamespace @import("arm_exec_scalar_bits.zig");

pub const ArmStepError = error{
    UnknownInstruction,
    Unpredictable,
    MissingRead,
    MissingWrite,
};

pub const AddResult = struct {
    word: u32,
    carry: bool,
    overflow: bool,
};

pub const ShiftResult = struct {
    word: u32,
    carry: bool,
};

pub const SaturatingWordResult = struct {
    word: u32,
    overflow: bool,
};

pub const FloatVectorPlan = struct {
    count: u32,
    stride: u32,
    source_scalar: bool,
};

pub const FloatBinaryOp = enum {
    add,
    sub,
    mul,
    neg_mul,
    div,
};

pub const FloatUnaryOp = enum {
    move,
    abs,
    neg,
    sqrt,
};

pub const CoprocessorOp = enum {
    command,
    load,
    send_word,
    send_pair,
    get_word,
    get_pair,
    store,
};

pub const ArmPattern = struct {
    mask: u32,
    expect: u32,
};

pub const external_arm_patterns = [_]ArmPattern{
    ArmPattern{ .mask = 0xfe000000, .expect = 0xfa000000 },
    ArmPattern{ .mask = 0x0ffffff0, .expect = 0x012fff30 },
    ArmPattern{ .mask = 0x0ffffff0, .expect = 0x012fff20 },
    ArmPattern{ .mask = 0xff000010, .expect = 0xfe000010 },
    ArmPattern{ .mask = 0x0f000010, .expect = 0x0e000000 },
    ArmPattern{ .mask = 0xfe100000, .expect = 0xfc100000 },
    ArmPattern{ .mask = 0x0e100000, .expect = 0x0c100000 },
    ArmPattern{ .mask = 0x0f100010, .expect = 0x0e000010 },
    ArmPattern{ .mask = 0xfff00000, .expect = 0xfc400000 },
    ArmPattern{ .mask = 0x0ff00000, .expect = 0x0c400000 },
    ArmPattern{ .mask = 0xff100010, .expect = 0xfe100010 },
    ArmPattern{ .mask = 0x0f100010, .expect = 0x0e100010 },
    ArmPattern{ .mask = 0xfff00000, .expect = 0xfc500000 },
    ArmPattern{ .mask = 0x0ff00000, .expect = 0x0c500000 },
    ArmPattern{ .mask = 0xfe100000, .expect = 0xfc000000 },
    ArmPattern{ .mask = 0x0e100000, .expect = 0x0c000000 },
    ArmPattern{ .mask = 0x0ff000f0, .expect = 0x01200070 },
    ArmPattern{ .mask = 0xfc70f000, .expect = 0xf450f000 },
    ArmPattern{ .mask = 0x0fffffff, .expect = 0x0320f004 },
    ArmPattern{ .mask = 0x0fffffff, .expect = 0x0320f002 },
    ArmPattern{ .mask = 0x0fffffff, .expect = 0x0320f003 },
    ArmPattern{ .mask = 0x0fffffff, .expect = 0x0320f001 },
    ArmPattern{ .mask = 0xffffffff, .expect = 0xf57ff01f },
    ArmPattern{ .mask = 0x0ff00fff, .expect = 0x01900f9f },
    ArmPattern{ .mask = 0x0ff00fff, .expect = 0x01d00f9f },
    ArmPattern{ .mask = 0x0ff00fff, .expect = 0x01b00f9f },
    ArmPattern{ .mask = 0x0ff00fff, .expect = 0x01f00f9f },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01800f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01c00f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01a00f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01e00f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01000090 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01400090 },
    ArmPattern{ .mask = 0x0f700000, .expect = 0x04700000 },
    ArmPattern{ .mask = 0x0f700010, .expect = 0x06700000 },
    ArmPattern{ .mask = 0x0f7000f0, .expect = 0x007000b0 },
    ArmPattern{ .mask = 0x0f700ff0, .expect = 0x003000b0 },
    ArmPattern{ .mask = 0x0e5000f0, .expect = 0x005000d0 },
    ArmPattern{ .mask = 0x0e500ff0, .expect = 0x001000d0 },
    ArmPattern{ .mask = 0x0f7000f0, .expect = 0x007000d0 },
    ArmPattern{ .mask = 0x0f700ff0, .expect = 0x003000d0 },
    ArmPattern{ .mask = 0x0e5000f0, .expect = 0x005000f0 },
    ArmPattern{ .mask = 0x0e500ff0, .expect = 0x001000f0 },
    ArmPattern{ .mask = 0x0f7000f0, .expect = 0x007000f0 },
    ArmPattern{ .mask = 0x0f700ff0, .expect = 0x003000f0 },
    ArmPattern{ .mask = 0x0f700000, .expect = 0x04300000 },
    ArmPattern{ .mask = 0x0f700010, .expect = 0x06300000 },
    ArmPattern{ .mask = 0x0f700000, .expect = 0x04600000 },
    ArmPattern{ .mask = 0x0f700010, .expect = 0x06600000 },
    ArmPattern{ .mask = 0x0f7000f0, .expect = 0x006000b0 },
    ArmPattern{ .mask = 0x0f700ff0, .expect = 0x002000b0 },
    ArmPattern{ .mask = 0x0f700000, .expect = 0x04200000 },
    ArmPattern{ .mask = 0x0f700010, .expect = 0x06200000 },
    ArmPattern{ .mask = 0x0e500000, .expect = 0x08100000 },
    ArmPattern{ .mask = 0x0e700000, .expect = 0x08500000 },
    ArmPattern{ .mask = 0x0e508000, .expect = 0x08508000 },
    ArmPattern{ .mask = 0x0e500000, .expect = 0x08000000 },
    ArmPattern{ .mask = 0x0e700000, .expect = 0x08400000 },
    ArmPattern{ .mask = 0x0fff0ff0, .expect = 0x016f0f10 },
    ArmPattern{ .mask = 0x0ffffff0, .expect = 0x0320f000 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06800fb0 },
    ArmPattern{ .mask = 0x0ff0f0f0, .expect = 0x0780f010 },
    ArmPattern{ .mask = 0x0ff000f0, .expect = 0x07800010 },
    ArmPattern{ .mask = 0x0ff00070, .expect = 0x06800010 },
    ArmPattern{ .mask = 0x0ff00070, .expect = 0x06800050 },
    ArmPattern{ .mask = 0x0fe00030, .expect = 0x06a00010 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06a00f30 },
    ArmPattern{ .mask = 0x0fe00030, .expect = 0x06e00010 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06e00f30 },
    ArmPattern{ .mask = 0x0ff00090, .expect = 0x01400080 },
    ArmPattern{ .mask = 0x0ff00090, .expect = 0x01000080 },
    ArmPattern{ .mask = 0x0ff0f090, .expect = 0x01600080 },
    ArmPattern{ .mask = 0x0ff000b0, .expect = 0x01200080 },
    ArmPattern{ .mask = 0x0ff0f0b0, .expect = 0x012000a0 },
    ArmPattern{ .mask = 0x0ff0f0d0, .expect = 0x0750f010 },
    ArmPattern{ .mask = 0x0ff000d0, .expect = 0x07500010 },
    ArmPattern{ .mask = 0x0ff000d0, .expect = 0x075000d0 },
    ArmPattern{ .mask = 0x0ff000d0, .expect = 0x07000010 },
    ArmPattern{ .mask = 0x0ff000d0, .expect = 0x07400010 },
    ArmPattern{ .mask = 0x0ff000d0, .expect = 0x07000050 },
    ArmPattern{ .mask = 0x0ff000d0, .expect = 0x07400050 },
    ArmPattern{ .mask = 0x0ff0f0d0, .expect = 0x0700f010 },
    ArmPattern{ .mask = 0x0ff0f0d0, .expect = 0x0700f050 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06100f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06100f10 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06100f30 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06100f50 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06100ff0 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06100f70 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06500f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06500f10 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06500f30 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06500f50 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06500ff0 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06500f70 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06200f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06200f10 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06200f30 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06200f50 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06200ff0 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06200f70 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06600f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06600f10 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06600f30 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06600f50 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06600ff0 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06600f70 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06300f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06300f10 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06300f30 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06300f50 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06300ff0 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06300f70 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06700f90 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06700f10 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06700f30 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06700f50 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06700ff0 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x06700f70 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01000050 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01200050 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01400050 },
    ArmPattern{ .mask = 0x0ff00ff0, .expect = 0x01600050 },
    ArmPattern{ .mask = 0xfff1fe20, .expect = 0xf1000000 },
    ArmPattern{ .mask = 0xfffffdff, .expect = 0xf1010000 },
    ArmPattern{ .mask = 0x0fb00cff, .expect = 0x01000000 },
    ArmPattern{ .mask = 0x0db0f000, .expect = 0x0120f000 },
    ArmPattern{ .mask = 0x0fef0070, .expect = 0x01a00060 },
    ArmPattern{ .mask = 0xfe5ffff0, .expect = 0x06000010 },
};

pub const DataOp = enum(u4) {
    bit_and = 0x0,
    bit_xor = 0x1,
    sub = 0x2,
    reverse_sub = 0x3,
    add = 0x4,
    add_carry = 0x5,
    sub_carry = 0x6,
    reverse_sub_carry = 0x7,
    test_and = 0x8,
    test_xor = 0x9,
    compare = 0xa,
    compare_negative = 0xb,
    bit_or = 0xc,
    move = 0xd,
    bit_clear = 0xe,
    move_not = 0xf,
};

pub const ShiftMode = enum(u2) {
    left,
    right,
    signed_right,
    rotate_right,
};

pub const ExtendOp = enum(u4) {
    signed_byte_pair_add,
    signed_byte_add,
    signed_half_add,
    signed_byte_pair,
    signed_byte,
    signed_half,
    unsigned_byte_pair,
    unsigned_byte_pair_add,
    unsigned_byte_add,
    unsigned_half_add,
    unsigned_byte,
    unsigned_half,
};

pub const MultiplyOp = enum(u4) {
    multiply,
    multiply_add,
    unsigned_long,
    unsigned_long_add,
    unsigned_accumulate,
    signed_long,
    signed_long_add,
};

pub const HalfMultiplyOp = enum(u3) {
    long_add,
    add,
    multiply,
    word_add,
    word_multiply,
};

pub const DualMultiplyOp = enum(u3) {
    add,
    long_add,
    sub,
    long_sub,
    pair_add,
    pair_sub,
};

