const bits = @import("bits.zig");

pub const status_mask: u32 = 0xf800009f;

pub const FloatStatus = struct {
    value: u32,

    pub fn init(value: u32) FloatStatus {
        return FloatStatus{ .value = value & status_mask };
    }

    pub fn raw(self: FloatStatus) u32 {
        return self.value;
    }

    pub fn negative(self: FloatStatus) bool {
        return bits.getBit32(self.value, 31);
    }

    pub fn setNegative(self: *FloatStatus, enabled: bool) void {
        self.value = bits.setBit32(self.value, 31, enabled) & status_mask;
    }

    pub fn zero(self: FloatStatus) bool {
        return bits.getBit32(self.value, 30);
    }

    pub fn setZero(self: *FloatStatus, enabled: bool) void {
        self.value = bits.setBit32(self.value, 30, enabled) & status_mask;
    }

    pub fn carry(self: FloatStatus) bool {
        return bits.getBit32(self.value, 29);
    }

    pub fn setCarry(self: *FloatStatus, enabled: bool) void {
        self.value = bits.setBit32(self.value, 29, enabled) & status_mask;
    }

    pub fn overflowFlag(self: FloatStatus) bool {
        return bits.getBit32(self.value, 28);
    }

    pub fn setOverflowFlag(self: *FloatStatus, enabled: bool) void {
        self.value = bits.setBit32(self.value, 28, enabled) & status_mask;
    }

    pub fn saturated(self: FloatStatus) bool {
        return bits.getBit32(self.value, 27);
    }

    pub fn setSaturated(self: *FloatStatus, enabled: bool) void {
        self.value = bits.setBit32(self.value, 27, enabled) & status_mask;
    }

    pub fn inputDenormal(self: FloatStatus) bool {
        return bits.getBit32(self.value, 7);
    }

    pub fn setInputDenormal(self: *FloatStatus, enabled: bool) void {
        self.value = bits.setBit32(self.value, 7, enabled) & status_mask;
    }

    pub fn inexact(self: FloatStatus) bool {
        return bits.getBit32(self.value, 4);
    }

    pub fn setInexact(self: *FloatStatus, enabled: bool) void {
        self.value = bits.setBit32(self.value, 4, enabled) & status_mask;
    }

    pub fn underflow(self: FloatStatus) bool {
        return bits.getBit32(self.value, 3);
    }

    pub fn setUnderflow(self: *FloatStatus, enabled: bool) void {
        self.value = bits.setBit32(self.value, 3, enabled) & status_mask;
    }

    pub fn overflow(self: FloatStatus) bool {
        return bits.getBit32(self.value, 2);
    }

    pub fn setOverflow(self: *FloatStatus, enabled: bool) void {
        self.value = bits.setBit32(self.value, 2, enabled) & status_mask;
    }

    pub fn divideByZero(self: FloatStatus) bool {
        return bits.getBit32(self.value, 1);
    }

    pub fn setDivideByZero(self: *FloatStatus, enabled: bool) void {
        self.value = bits.setBit32(self.value, 1, enabled) & status_mask;
    }

    pub fn invalidOperation(self: FloatStatus) bool {
        return bits.getBit32(self.value, 0);
    }

    pub fn setInvalidOperation(self: *FloatStatus, enabled: bool) void {
        self.value = bits.setBit32(self.value, 0, enabled) & status_mask;
    }
};
