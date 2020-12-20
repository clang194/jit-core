const bits = @import("bits.zig");

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

pub const FloatRoundMode = enum(u2) {
    nearest = 0,
    positive = 1,
    negative = 2,
    zero = 3,
};

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

pub const HostHooks = struct {
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
    fallback: ?fn (u32, *MachineState, ?*c_void) void,
    context: ?*c_void,
    trap: ?fn (u32) bool,
    supervisor: ?fn (u32, *MachineState) void,
    direct_pages: ?*PageMap,

    pub fn empty() HostHooks {
        return HostHooks{
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
            .fallback = null,
            .context = null,
            .trap = null,
            .supervisor = null,
            .direct_pages = null,
        };
    }

    fn directPage(self: HostHooks, address: u32, comptime width: usize) ?DirectPage {
        const offset = @intCast(usize, address & (page_size - 1));
        if (offset + width > page_size) {
            return null;
        }
        const table = self.direct_pages orelse return null;
        const page = table.*[@intCast(usize, address >> page_bits)] orelse return null;
        return DirectPage{ .bytes = page, .offset = offset };
    }

    pub fn readDirect8(self: HostHooks, address: u32) ?u8 {
        const page = self.directPage(address, 1) orelse return null;
        return page.bytes[page.offset];
    }

    pub fn readDirect16(self: HostHooks, address: u32) ?u16 {
        const page = self.directPage(address, 2) orelse return null;
        return @as(u16, page.bytes[page.offset]) |
            (@as(u16, page.bytes[page.offset + 1]) << 8);
    }

    pub fn readDirect32(self: HostHooks, address: u32) ?u32 {
        const page = self.directPage(address, 4) orelse return null;
        return @as(u32, page.bytes[page.offset]) |
            (@as(u32, page.bytes[page.offset + 1]) << 8) |
            (@as(u32, page.bytes[page.offset + 2]) << 16) |
            (@as(u32, page.bytes[page.offset + 3]) << 24);
    }

    pub fn readDirect64(self: HostHooks, address: u32) ?u64 {
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

    pub fn writeDirect8(self: HostHooks, address: u32, value: u8) bool {
        const page = self.directPage(address, 1) orelse return false;
        page.bytes[page.offset] = value;
        return true;
    }

    pub fn writeDirect16(self: HostHooks, address: u32, value: u16) bool {
        const page = self.directPage(address, 2) orelse return false;
        page.bytes[page.offset] = @intCast(u8, value & 0xff);
        page.bytes[page.offset + 1] = @intCast(u8, value >> 8);
        return true;
    }

    pub fn writeDirect32(self: HostHooks, address: u32, value: u32) bool {
        const page = self.directPage(address, 4) orelse return false;
        page.bytes[page.offset] = @intCast(u8, value & 0xff);
        page.bytes[page.offset + 1] = @intCast(u8, (value >> 8) & 0xff);
        page.bytes[page.offset + 2] = @intCast(u8, (value >> 16) & 0xff);
        page.bytes[page.offset + 3] = @intCast(u8, value >> 24);
        return true;
    }

    pub fn writeDirect64(self: HostHooks, address: u32, value: u64) bool {
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
        return ((self.fpscr >> 20) & 0x3) + 1;
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
