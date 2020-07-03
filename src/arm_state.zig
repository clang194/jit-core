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
        };
    }
};

pub const MachineState = struct {
    regs: [16]u32,
    cpsr: u32,

    pub fn zeroed() MachineState {
        return MachineState{
            .regs = [_]u32{0} ** 16,
            .cpsr = 0,
        };
    }

    pub fn read(self: *const MachineState, reg: ArmReg) u32 {
        return self.regs[@enumToInt(reg)];
    }

    pub fn write(self: *MachineState, reg: ArmReg, value: u32) void {
        self.regs[@enumToInt(reg)] = value;
    }

    pub fn carry(self: *const MachineState) bool {
        return bits.getBit32(self.cpsr, 29);
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

