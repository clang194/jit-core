const bits = @import("bits.zig");
const float_rounding = @import("float_rounding.zig");

pub const Mode = float_rounding.RoundingMode;
pub const mask: u32 = 0x07ff9f00;
pub const key_mask: u32 = 0x07c00000;

pub const ControlError = error{
    OutOfRange,
};

pub fn clean(value: u32) u32 {
    return value & mask;
}

pub const Control = struct {
    value: u32,

    pub fn init(value: u32) Control {
        return Control{ .value = clean(value) };
    }

    pub fn raw(self: Control) u32 {
        return self.value;
    }

    pub fn ahp(self: Control) bool {
        return bits.getBit32(self.value, 26);
    }

    pub fn setAhp(self: *Control, enabled: bool) void {
        self.value = clean(bits.setBit32(self.value, 26, enabled));
    }

    pub fn dn(self: Control) bool {
        return bits.getBit32(self.value, 25);
    }

    pub fn setDn(self: *Control, enabled: bool) void {
        self.value = clean(bits.setBit32(self.value, 25, enabled));
    }

    pub fn fz(self: Control) bool {
        return bits.getBit32(self.value, 24);
    }

    pub fn setFz(self: *Control, enabled: bool) void {
        self.value = clean(bits.setBit32(self.value, 24, enabled));
    }

    pub fn fz16(self: Control) bool {
        return bits.getBit32(self.value, 19);
    }

    pub fn setFz16(self: *Control, enabled: bool) void {
        self.value = clean(bits.setBit32(self.value, 19, enabled));
    }

    pub fn rounding(self: Control) Mode {
        return @intToEnum(Mode, @intCast(u3, (self.value >> 22) & 3));
    }

    pub fn setRounding(self: *Control, mode: Mode) void {
        self.value = clean(bits.modifyBits32(self.value, @intCast(u32, @enumToInt(mode)), 22, 23));
    }

    pub fn vectorLength(self: Control) u32 {
        return ((self.value >> 16) & 7) + 1;
    }

    pub fn setVectorLength(self: *Control, length: u32) ControlError!void {
        if (length < 1 or length > 8) {
            return error.OutOfRange;
        }
        self.value = clean(bits.modifyBits32(self.value, length - 1, 16, 18));
    }

    pub fn vectorStride(self: Control) ?u32 {
        const encoded = (self.value >> 20) & 3;
        if (encoded == 0) {
            return 1;
        }
        if (encoded == 3) {
            return 2;
        }
        return null;
    }

    pub fn setVectorStride(self: *Control, stride: u32) ControlError!void {
        const encoded = if (stride == 1) @as(u32, 0) else if (stride == 2) @as(u32, 3) else return error.OutOfRange;
        self.value = clean(bits.modifyBits32(self.value, encoded, 20, 21));
    }

    pub fn ide(self: Control) bool {
        return bits.getBit32(self.value, 15);
    }

    pub fn setIde(self: *Control, enabled: bool) void {
        self.value = clean(bits.setBit32(self.value, 15, enabled));
    }

    pub fn ixe(self: Control) bool {
        return bits.getBit32(self.value, 12);
    }

    pub fn setIxe(self: *Control, enabled: bool) void {
        self.value = clean(bits.setBit32(self.value, 12, enabled));
    }

    pub fn ufe(self: Control) bool {
        return bits.getBit32(self.value, 11);
    }

    pub fn setUfe(self: *Control, enabled: bool) void {
        self.value = clean(bits.setBit32(self.value, 11, enabled));
    }

    pub fn ofe(self: Control) bool {
        return bits.getBit32(self.value, 10);
    }

    pub fn setOfe(self: *Control, enabled: bool) void {
        self.value = clean(bits.setBit32(self.value, 10, enabled));
    }

    pub fn dze(self: Control) bool {
        return bits.getBit32(self.value, 9);
    }

    pub fn setDze(self: *Control, enabled: bool) void {
        self.value = clean(bits.setBit32(self.value, 9, enabled));
    }

    pub fn ioe(self: Control) bool {
        return bits.getBit32(self.value, 8);
    }

    pub fn setIoe(self: *Control, enabled: bool) void {
        self.value = clean(bits.setBit32(self.value, 8, enabled));
    }
};
