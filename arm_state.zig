const bits = @import("bits.zig");

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
    read8: ?fn (u32) u8,
    read16: ?fn (u32) u16,
    read32: ?fn (u32) u32,
    read64: ?fn (u32) u64,
    write8: ?fn (u32, u8) void,
    write16: ?fn (u32, u16) void,
    write32: ?fn (u32, u32) void,
    write64: ?fn (u32, u64) void,
    readOnly: ?fn (u32) bool,
    fallback: ?fn (u32, *MachineState) void,
    trap: ?fn (u32) bool,
    supervisor: ?fn (u32, *MachineState) void,

    pub fn empty() HostHooks {
        return HostHooks{
            .read8 = null,
            .read16 = null,
            .read32 = null,
            .read64 = null,
            .write8 = null,
            .write16 = null,
            .write32 = null,
            .write64 = null,
            .readOnly = null,
            .fallback = null,
            .trap = null,
            .supervisor = null,
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
