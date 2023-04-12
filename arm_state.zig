const bits = @import("bits.zig");
const float_rounding = @import("float_rounding.zig");

const DirectPage = struct {
    bytes: [*]u8,
    offset: usize,
};

pub const ArmReg = enum(u8) {
    r0,
    r1,
    r2,
    r3,
    r4,
    r5,
    r6,
    r7,
    r8,
    r9,
    r10,
    r11,
    r12,
    sp,
    lr,
    pc,
};

pub const ConditionCode = enum(u4) {
    eq = 0x0,
    ne = 0x1,
    cs = 0x2,
    cc = 0x3,
    mi = 0x4,
    pl = 0x5,
    vs = 0x6,
    vc = 0x7,
    hi = 0x8,
    ls = 0x9,
    ge = 0xa,
    lt = 0xb,
    gt = 0xc,
    le = 0xd,
    al = 0xe,
    nv = 0xf,
};

pub const IfThenState = struct {
    value: u8,

    pub fn init(value: u8) IfThenState {
        return IfThenState{ .value = value };
    }

    pub fn raw(self: IfThenState) u8 {
        return self.value;
    }

    pub fn condition(self: IfThenState) ?ConditionCode {
        return conditionFromNibble(@intCast(u4, self.value >> 4));
    }

    pub fn setCondition(self: *IfThenState, code: ConditionCode) void {
        self.value = (self.value & 0x0f) | (@as(u8, @enumToInt(code)) << 4);
    }

    pub fn mask(self: IfThenState) u8 {
        return self.value & 0x0f;
    }

    pub fn setMask(self: *IfThenState, value: u8) void {
        self.value = (self.value & 0xf0) | (value & 0x0f);
    }

    pub fn active(self: IfThenState) bool {
        return self.mask() != 0;
    }

    pub fn last(self: IfThenState) bool {
        return self.mask() == 0x8;
    }

    pub fn advance(self: IfThenState) IfThenState {
        var next = self;
        next.setMask(next.mask() << 1);
        if (next.mask() == 0) {
            return IfThenState.init(0);
        }
        return next;
    }
};

pub const FloatRoundMode = float_rounding.RoundingMode;

pub const float_status_mask: u32 = 0xfff79f9f;

pub fn cleanFloatStatus(value: u32) u32 {
    return value & float_status_mask;
}

pub const FloatWordReg = enum(u5) {
    s0,
    s1,
    s2,
    s3,
    s4,
    s5,
    s6,
    s7,
    s8,
    s9,
    s10,
    s11,
    s12,
    s13,
    s14,
    s15,
    s16,
    s17,
    s18,
    s19,
    s20,
    s21,
    s22,
    s23,
    s24,
    s25,
    s26,
    s27,
    s28,
    s29,
    s30,
    s31,
};

pub const FloatPairReg = enum(u5) {
    d0,
    d1,
    d2,
    d3,
    d4,
    d5,
    d6,
    d7,
    d8,
    d9,
    d10,
    d11,
    d12,
    d13,
    d14,
    d15,
    d16,
    d17,
    d18,
    d19,
    d20,
    d21,
    d22,
    d23,
    d24,
    d25,
    d26,
    d27,
    d28,
    d29,
    d30,
    d31,
};

pub const CoprocessorReg = enum(u4) {
    c0,
    c1,
    c2,
    c3,
    c4,
    c5,
    c6,
    c7,
    c8,
    c9,
    c10,
    c11,
    c12,
    c13,
    c14,
    c15,
};

pub const CoprocessorCommand = struct {
    extended: bool,
    op1: u4,
    dest: CoprocessorReg,
    base: CoprocessorReg,
    operand: CoprocessorReg,
    op2: u3,
};

pub const CoprocessorWord = struct {
    extended: bool,
    op1: u3,
    base: CoprocessorReg,
    operand: CoprocessorReg,
    op2: u3,
};

pub const CoprocessorPair = struct {
    extended: bool,
    op: u4,
    operand: CoprocessorReg,
};

pub const CoprocessorBlock = struct {
    extended: bool,
    long: bool,
    register: CoprocessorReg,
    option: ?u8,
};

pub const CoprocessorHooks = struct {
    operate: ?fn (*MachineState, CoprocessorCommand, ?*anyopaque) void,
    sendWord: ?fn (*MachineState, CoprocessorWord, u32, ?*anyopaque) void,
    sendPair: ?fn (*MachineState, CoprocessorPair, u32, u32, ?*anyopaque) void,
    getWord: ?fn (*MachineState, CoprocessorWord, ?*anyopaque) u32,
    getPair: ?fn (*MachineState, CoprocessorPair, ?*anyopaque) u64,
    loadBlock: ?fn (*MachineState, CoprocessorBlock, u32, ?*anyopaque) void,
    storeBlock: ?fn (*MachineState, CoprocessorBlock, u32, ?*anyopaque) void,
    context: ?*anyopaque,

    pub fn empty() CoprocessorHooks {
        return CoprocessorHooks{
            .operate = null,
            .sendWord = null,
            .sendPair = null,
            .getWord = null,
            .getPair = null,
            .loadBlock = null,
            .storeBlock = null,
            .context = null,
        };
    }
};

pub const MemoryHooks = struct {
    pub const page_bits = 12;
    pub const page_size = @as(usize, 1) << page_bits;
    pub const page_count = @as(usize, 1) << (32 - page_bits);
    pub const PageMap = [page_count]?[*]u8;

    read8: ?fn (u32) u8,
    read16: ?fn (u32) u16,
    read32: ?fn (u32) u32,
    read64: ?fn (u32) u64,
    fetch32: ?fn (u32) u32,
    write8: ?fn (u32, u8) void,
    write16: ?fn (u32, u16) void,
    write32: ?fn (u32, u32) void,
    write64: ?fn (u32, u64) void,
    readOnly: ?fn (u32) bool,
    direct_pages: ?*PageMap,
    direct_full_address: bool,

    pub fn empty() MemoryHooks {
        return MemoryHooks{
            .read8 = null,
            .read16 = null,
            .read32 = null,
            .read64 = null,
            .fetch32 = null,
            .write8 = null,
            .write16 = null,
            .write32 = null,
            .write64 = null,
            .readOnly = null,
            .direct_pages = null,
            .direct_full_address = false,
        };
    }

    fn directPage(self: MemoryHooks, address: u32, comptime width: usize) ?DirectPage {
        const page_offset = @intCast(usize, address & (page_size - 1));
        if (!self.direct_full_address and page_offset + width > page_size) {
            return null;
        }
        const table = self.direct_pages orelse return null;
        const page = table.*[@intCast(usize, address >> page_bits)] orelse return null;
        const offset = if (self.direct_full_address) @intCast(usize, address) else page_offset;
        return DirectPage{ .bytes = page, .offset = offset };
    }

    pub fn readDirect8(self: MemoryHooks, address: u32) ?u8 {
        const page = self.directPage(address, 1) orelse return null;
        return page.bytes[page.offset];
    }

    pub fn readDirect16(self: MemoryHooks, address: u32) ?u16 {
        const page = self.directPage(address, 2) orelse return null;
        return @as(u16, page.bytes[page.offset]) |
            (@as(u16, page.bytes[page.offset + 1]) << 8);
    }

    pub fn readDirect32(self: MemoryHooks, address: u32) ?u32 {
        const page = self.directPage(address, 4) orelse return null;
        return @as(u32, page.bytes[page.offset]) |
            (@as(u32, page.bytes[page.offset + 1]) << 8) |
            (@as(u32, page.bytes[page.offset + 2]) << 16) |
            (@as(u32, page.bytes[page.offset + 3]) << 24);
    }

    pub fn readDirect64(self: MemoryHooks, address: u32) ?u64 {
        const page = self.directPage(address, 8) orelse return null;
        const low = @as(u32, page.bytes[page.offset]) |
            (@as(u32, page.bytes[page.offset + 1]) << 8) |
            (@as(u32, page.bytes[page.offset + 2]) << 16) |
            (@as(u32, page.bytes[page.offset + 3]) << 24);
        const high = @as(u32, page.bytes[page.offset + 4]) |
            (@as(u32, page.bytes[page.offset + 5]) << 8) |
            (@as(u32, page.bytes[page.offset + 6]) << 16) |
            (@as(u32, page.bytes[page.offset + 7]) << 24);
        return @as(u64, low) | (@as(u64, high) << 32);
    }

    pub fn writeDirect8(self: MemoryHooks, address: u32, value: u8) bool {
        const page = self.directPage(address, 1) orelse return false;
        page.bytes[page.offset] = value;
        return true;
    }

    pub fn writeDirect16(self: MemoryHooks, address: u32, value: u16) bool {
        const page = self.directPage(address, 2) orelse return false;
        page.bytes[page.offset] = @intCast(u8, value & 0xff);
        page.bytes[page.offset + 1] = @intCast(u8, value >> 8);
        return true;
    }

    pub fn writeDirect32(self: MemoryHooks, address: u32, value: u32) bool {
        const page = self.directPage(address, 4) orelse return false;
        page.bytes[page.offset] = @intCast(u8, value & 0xff);
        page.bytes[page.offset + 1] = @intCast(u8, (value >> 8) & 0xff);
        page.bytes[page.offset + 2] = @intCast(u8, (value >> 16) & 0xff);
        page.bytes[page.offset + 3] = @intCast(u8, value >> 24);
        return true;
    }

    pub fn writeDirect64(self: MemoryHooks, address: u32, value: u64) bool {
        const page = self.directPage(address, 8) orelse return false;
        page.bytes[page.offset] = @intCast(u8, value & 0xff);
        page.bytes[page.offset + 1] = @intCast(u8, (value >> 8) & 0xff);
        page.bytes[page.offset + 2] = @intCast(u8, (value >> 16) & 0xff);
        page.bytes[page.offset + 3] = @intCast(u8, (value >> 24) & 0xff);
        page.bytes[page.offset + 4] = @intCast(u8, (value >> 32) & 0xff);
        page.bytes[page.offset + 5] = @intCast(u8, (value >> 40) & 0xff);
        page.bytes[page.offset + 6] = @intCast(u8, (value >> 48) & 0xff);
        page.bytes[page.offset + 7] = @intCast(u8, value >> 56);
        return true;
    }
};

pub const FaultKind = enum {
    undefined_instruction,
    unpredictable_instruction,
    breakpoint,
};

pub const SystemHint = enum {
    preload_data,
    preload_data_write,
    send_event,
    send_event_local,
    wait_interrupt,
    wait_event,
    yield_hint,
};

pub const HostHooks = struct {
    pub const CycleHooks = struct {
        add: ?fn (usize, ?*anyopaque) void,
        remaining: ?fn (?*anyopaque) usize,

        pub fn empty() CycleHooks {
            return CycleHooks{
                .add = null,
                .remaining = null,
            };
        }
    };

    memory: MemoryHooks,
    fallback: ?fn (u32, *MachineState, ?*anyopaque) void,
    context: ?*anyopaque,
    trap: ?fn (u32) bool,
    supervisor: ?fn (u32, *MachineState) void,
    exception: ?fn (u32, FaultKind, *MachineState, ?*anyopaque) void,
    system_hint: ?fn (u32, SystemHint, *MachineState, ?*anyopaque) void,
    instruction_barrier: ?fn (?*anyopaque) void,
    coprocessors: [16]?CoprocessorHooks,
    cycles: CycleHooks,
    resolve_unpredictable_cases: bool,
    hook_hints: bool,
    keep_little_endian: bool,

    pub fn empty() HostHooks {
        return HostHooks{
            .memory = MemoryHooks.empty(),
            .fallback = null,
            .context = null,
            .trap = null,
            .supervisor = null,
            .exception = null,
            .system_hint = null,
            .instruction_barrier = null,
            .coprocessors = [_]?CoprocessorHooks{null} ** 16,
            .cycles = CycleHooks.empty(),
            .resolve_unpredictable_cases = false,
            .hook_hints = false,
            .keep_little_endian = false,
        };
    }
};

pub const MachineState = struct {
    regs: [16]u32,
    float_regs: [64]u32,
    cpsr: u32,
    fpscr: u32,
    exclusive: bool,
    exclusive_address: u32,

    pub fn zeroed() MachineState {
        return MachineState{
            .regs = [_]u32{0} ** 16,
            .float_regs = [_]u32{0} ** 64,
            .cpsr = 0,
            .fpscr = 0,
            .exclusive = false,
            .exclusive_address = 0,
        };
    }

    pub fn read(self: *const MachineState, reg: ArmReg) u32 {
        return self.regs[@enumToInt(reg)];
    }

    pub fn write(self: *MachineState, reg: ArmReg, value: u32) void {
        self.regs[@enumToInt(reg)] = value;
    }

    pub fn readFloatWord(self: *const MachineState, reg: FloatWordReg) u32 {
        return self.float_regs[@enumToInt(reg)];
    }

    pub fn writeFloatWord(self: *MachineState, reg: FloatWordReg, value: u32) void {
        self.float_regs[@enumToInt(reg)] = value;
    }

    pub fn readFloatPair(self: *const MachineState, reg: FloatPairReg) u64 {
        const index = @as(usize, @enumToInt(reg)) * 2;
        return @as(u64, self.float_regs[index]) | (@as(u64, self.float_regs[index + 1]) << 32);
    }

    pub fn writeFloatPair(self: *MachineState, reg: FloatPairReg, value: u64) void {
        const index = @as(usize, @enumToInt(reg)) * 2;
        self.float_regs[index] = @intCast(u32, value & 0xffffffff);
        self.float_regs[index + 1] = @intCast(u32, value >> 32);
    }

    pub fn readFloatStatus(self: *const MachineState) u32 {
        return cleanFloatStatus(self.fpscr);
    }

    pub fn writeFloatStatus(self: *MachineState, value: u32) void {
        self.fpscr = cleanFloatStatus(value);
    }

    pub fn carry(self: *const MachineState) bool {
        return bits.getBit32(self.cpsr, 29);
    }

    pub fn negative(self: *const MachineState) bool {
        return bits.getBit32(self.cpsr, 31);
    }

    pub fn zero(self: *const MachineState) bool {
        return bits.getBit32(self.cpsr, 30);
    }

    pub fn overflow(self: *const MachineState) bool {
        return bits.getBit32(self.cpsr, 28);
    }

    pub fn readGreaterEqualLanes(self: *const MachineState) u32 {
        return (self.cpsr >> 16) & 0xf;
    }

    pub fn writeGreaterEqualLanes(self: *MachineState, value: u32) void {
        self.cpsr = (self.cpsr & ~@as(u32, 0x000f0000)) | ((value & 0xf) << 16);
    }

    pub fn readIfThenState(self: *const MachineState) IfThenState {
        const high = @intCast(u8, (self.cpsr >> 8) & 0xfc);
        const low = @intCast(u8, (self.cpsr >> 25) & 0x03);
        return IfThenState.init(high | low);
    }

    pub fn writeIfThenState(self: *MachineState, value: IfThenState) void {
        const raw = value.raw();
        const with_high = bits.modifyBits32(self.cpsr, @as(u32, raw >> 2), 10, 15);
        self.cpsr = bits.modifyBits32(with_high, @as(u32, raw & 0x03), 25, 26);
    }

    pub fn advanceIfThenState(self: *MachineState) void {
        self.writeIfThenState(self.readIfThenState().advance());
    }

    pub fn conditionHolds(self: *const MachineState, code: ConditionCode) bool {
        const n = self.negative();
        const z = self.zero();
        const c = self.carry();
        const v = self.overflow();
        return switch (code) {
            .eq => z,
            .ne => !z,
            .cs => c,
            .cc => !c,
            .mi => n,
            .pl => !n,
            .vs => v,
            .vc => !v,
            .hi => c and !z,
            .ls => !c or z,
            .ge => n == v,
            .lt => n != v,
            .gt => !z and n == v,
            .le => z or n != v,
            .al => true,
            .nv => false,
        };
    }

    pub fn thumb(self: *const MachineState) bool {
        return bits.getBit32(self.cpsr, 5);
    }

    pub fn bigEndian(self: *const MachineState) bool {
        return bits.getBit32(self.cpsr, 9);
    }

    pub fn floatRoundMode(self: *const MachineState) FloatRoundMode {
        return @intToEnum(FloatRoundMode, @intCast(u2, (self.fpscr >> 22) & 3));
    }

    pub fn floatFlushZero(self: *const MachineState) bool {
        return bits.getBit32(self.fpscr, 24);
    }

    pub fn floatDefaultNaN(self: *const MachineState) bool {
        return bits.getBit32(self.fpscr, 25);
    }

    pub fn floatVectorLength(self: *const MachineState) u32 {
        return ((self.fpscr >> 16) & 0x7) + 1;
    }

    pub fn floatVectorStride(self: *const MachineState) u32 {
        const stride = (self.fpscr >> 20) & 0x3;
        if (stride == 0) {
            return 1;
        }
        if (stride == 3) {
            return 2;
        }
        return 0;
    }

    pub fn setThumb(self: *MachineState, enabled: bool) void {
        self.cpsr = bits.setBit32(self.cpsr, 5, enabled);
    }

    pub fn setBigEndian(self: *MachineState, enabled: bool) void {
        self.cpsr = bits.setBit32(self.cpsr, 9, enabled);
    }

    pub fn setNegative(self: *MachineState, enabled: bool) void {
        self.cpsr = bits.setBit32(self.cpsr, 31, enabled);
    }

    pub fn setZero(self: *MachineState, enabled: bool) void {
        self.cpsr = bits.setBit32(self.cpsr, 30, enabled);
    }

    pub fn setCarry(self: *MachineState, enabled: bool) void {
        self.cpsr = bits.setBit32(self.cpsr, 29, enabled);
    }

    pub fn setOverflow(self: *MachineState, enabled: bool) void {
        self.cpsr = bits.setBit32(self.cpsr, 28, enabled);
    }
};

pub fn lowReg(value: u16) ArmReg {
    return @intToEnum(ArmReg, @intCast(u8, value & 7));
}

pub fn reg4(value: u16) ArmReg {
    return @intToEnum(ArmReg, @intCast(u8, value & 15));
}

pub fn regName(reg: ArmReg) []const u8 {
    return switch (reg) {
        .r0 => "r0",
        .r1 => "r1",
        .r2 => "r2",
        .r3 => "r3",
        .r4 => "r4",
        .r5 => "r5",
        .r6 => "r6",
        .r7 => "r7",
        .r8 => "r8",
        .r9 => "r9",
        .r10 => "r10",
        .r11 => "r11",
        .r12 => "r12",
        .sp => "sp",
        .lr => "lr",
        .pc => "pc",
    };
}

pub fn coprocessorRegName(reg: CoprocessorReg) []const u8 {
    return switch (reg) {
        .c0 => "c0",
        .c1 => "c1",
        .c2 => "c2",
        .c3 => "c3",
        .c4 => "c4",
        .c5 => "c5",
        .c6 => "c6",
        .c7 => "c7",
        .c8 => "c8",
        .c9 => "c9",
        .c10 => "c10",
        .c11 => "c11",
        .c12 => "c12",
        .c13 => "c13",
        .c14 => "c14",
        .c15 => "c15",
    };
}

pub fn conditionFromNibble(value: u4) ?ConditionCode {
    if (value == 0xf) {
        return null;
    }
    return @intToEnum(ConditionCode, value);
}

pub fn conditionSuffix(code: ConditionCode) []const u8 {
    return switch (code) {
        .eq => "eq",
        .ne => "ne",
        .cs => "cs",
        .cc => "cc",
        .mi => "mi",
        .pl => "pl",
        .vs => "vs",
        .vc => "vc",
        .hi => "hi",
        .ls => "ls",
        .ge => "ge",
        .lt => "lt",
        .gt => "gt",
        .le => "le",
        .al => "",
        .nv => "nv",
    };
}
