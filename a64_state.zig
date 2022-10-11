const bits = @import("bits.zig");
const float_control = @import("float_control.zig");

pub const FloatControlMode = float_control.Mode;

pub const float_control_mask: u32 = float_control.mask;
pub const float_control_key_mask: u32 = float_control.key_mask;
pub const float_status_mask: u32 = 0x0800009f;
pub const pc_mask: u64 = 0x00ffffffffffffff;

pub fn cleanFloatControl(value: u32) u32 {
    return float_control.clean(value);
}

pub fn cleanFloatStatus(value: u32) u32 {
    return value & float_status_mask;
}

pub const FloatControl = float_control.Control;

pub const BlockKey = struct {
    pc: u64,
    fpcr: u32,

    pub fn init(pc: u64, fpcr: FloatControl) BlockKey {
        return BlockKey{
            .pc = pc & pc_mask,
            .fpcr = fpcr.raw() & float_control_key_mask,
        };
    }

    pub fn fromRaw(value: u64) BlockKey {
        return BlockKey{
            .pc = value & pc_mask,
            .fpcr = @intCast(u32, (value >> 37) & float_control_key_mask),
        };
    }

    pub fn readPc(self: BlockKey) u64 {
        return @bitCast(u64, bits.signExtend64(self.pc, 56));
    }

    pub fn readFloatControl(self: BlockKey) FloatControl {
        return FloatControl.init(self.fpcr);
    }

    pub fn withPc(self: BlockKey, value: u64) BlockKey {
        return BlockKey.init(value, self.readFloatControl());
    }

    pub fn advance(self: BlockKey, amount: i64) BlockKey {
        return BlockKey.init(@bitCast(u64, @bitCast(i64, self.readPc()) + amount), self.readFloatControl());
    }

    pub fn raw(self: BlockKey) u64 {
        return (self.pc & pc_mask) | (@as(u64, self.fpcr & float_control_key_mask) << 37);
    }
};

pub const GeneralReg = enum(u5) {
    x0,
    x1,
    x2,
    x3,
    x4,
    x5,
    x6,
    x7,
    x8,
    x9,
    x10,
    x11,
    x12,
    x13,
    x14,
    x15,
    x16,
    x17,
    x18,
    x19,
    x20,
    x21,
    x22,
    x23,
    x24,
    x25,
    x26,
    x27,
    x28,
    x29,
    x30,
    sp,
};

pub const VectorReg = enum(u5) {
    v0,
    v1,
    v2,
    v3,
    v4,
    v5,
    v6,
    v7,
    v8,
    v9,
    v10,
    v11,
    v12,
    v13,
    v14,
    v15,
    v16,
    v17,
    v18,
    v19,
    v20,
    v21,
    v22,
    v23,
    v24,
    v25,
    v26,
    v27,
    v28,
    v29,
    v30,
    v31,
};

pub const ShiftKind = enum {
    lsl,
    lsr,
    asr,
    ror,
};

pub const VectorValue = struct {
    low: u64,
    high: u64,
};

pub const VectorOrder = enum {
    before,
    same,
    after,
};

fn wideFromVectorValue(value: VectorValue) u128 {
    return (@as(u128, value.high) << 64) | @as(u128, value.low);
}

fn vectorValueFromWide(value: u128) VectorValue {
    return VectorValue{
        .low = @truncate(u64, value),
        .high = @truncate(u64, value >> 64),
    };
}

pub fn rankVectorValue(left: VectorValue, right: VectorValue) VectorOrder {
    if (left.high < right.high) {
        return .before;
    }
    if (left.high > right.high) {
        return .after;
    }
    if (left.low < right.low) {
        return .before;
    }
    if (left.low > right.low) {
        return .after;
    }
    return .same;
}

pub fn vectorValueBit(value: VectorValue, comptime index: usize) bool {
    if (index >= 128) {
        @compileError("invalid bit index");
    }
    if (index < 64) {
        return bits.getBit64(value.low, @intCast(u6, index));
    }
    return bits.getBit64(value.high, @intCast(u6, index - 64));
}

pub fn multiplyWide(left: u64, right: u64) VectorValue {
    const product = @as(u128, left) * @as(u128, right);
    return VectorValue{
        .low = @truncate(u64, product),
        .high = @truncate(u64, product >> 64),
    };
}

fn shiftLeftPlainWide(value: VectorValue, amount: i32) VectorValue {
    if (amount <= 0) {
        return value;
    }
    if (amount >= 128) {
        return VectorValue{ .low = 0, .high = 0 };
    }
    return vectorValueFromWide(wideFromVectorValue(value) << @intCast(u7, amount));
}

pub fn shiftRightStickyWide(value: VectorValue, amount: i32) VectorValue {
    if (amount < 0) {
        return shiftLeftPlainWide(value, -amount);
    }
    if (amount == 0) {
        return value;
    }

    const wide = wideFromVectorValue(value);
    if (amount >= 128) {
        return VectorValue{ .low = if (wide == 0) 0 else 1, .high = 0 };
    }

    const shift = @intCast(u7, amount);
    const shifted = wide >> shift;
    const lost = wide & ((@as(u128, 1) << shift) - 1);
    return vectorValueFromWide(shifted | if (lost == 0) @as(u128, 0) else @as(u128, 1));
}

pub fn vectorValueBefore(left: VectorValue, right: VectorValue) bool {
    return rankVectorValue(left, right) == .before;
}

pub fn vectorValueAfter(left: VectorValue, right: VectorValue) bool {
    return rankVectorValue(left, right) == .after;
}

pub fn vectorValueSame(left: VectorValue, right: VectorValue) bool {
    return rankVectorValue(left, right) == .same;
}

pub fn vectorValueDifferent(left: VectorValue, right: VectorValue) bool {
    return !vectorValueSame(left, right);
}

pub fn vectorValueAtMost(left: VectorValue, right: VectorValue) bool {
    return rankVectorValue(left, right) != .after;
}

pub fn vectorValueAtLeast(left: VectorValue, right: VectorValue) bool {
    return rankVectorValue(left, right) != .before;
}

pub const MachineState64 = struct {
    regs: [31]u64,
    sp: u64,
    pc: u64,
    vectors: [32]VectorValue,
    fpcr: u32,
    fpsr: u32,
    nzcv: u32,
    exclusive: bool,
    exclusive_address: u64,

    pub fn zeroed() MachineState64 {
        return MachineState64{
            .regs = [_]u64{0} ** 31,
            .sp = 0,
            .pc = 0,
            .vectors = [_]VectorValue{VectorValue{ .low = 0, .high = 0 }} ** 32,
            .fpcr = 0,
            .fpsr = 0,
            .nzcv = 0,
            .exclusive = false,
            .exclusive_address = 0,
        };
    }

    pub fn read(self: *const MachineState64, reg: GeneralReg) u64 {
        if (reg == .sp) {
            return self.sp;
        }
        return self.regs[@enumToInt(reg)];
    }

    pub fn write(self: *MachineState64, reg: GeneralReg, value: u64) void {
        if (reg == .sp) {
            self.sp = value;
            return;
        }
        self.regs[@enumToInt(reg)] = value;
    }

    pub fn readVector(self: *const MachineState64, reg: VectorReg) VectorValue {
        return self.vectors[@enumToInt(reg)];
    }

    pub fn writeVector(self: *MachineState64, reg: VectorReg, value: VectorValue) void {
        self.vectors[@enumToInt(reg)] = value;
    }

    pub fn floatControl(self: *const MachineState64) FloatControl {
        return FloatControl.init(self.fpcr);
    }

    pub fn writeFloatControl(self: *MachineState64, value: u32) void {
        self.fpcr = cleanFloatControl(value);
    }

    pub fn floatStatus(self: *const MachineState64) u32 {
        return self.fpsr & float_status_mask;
    }

    pub fn writeFloatStatus(self: *MachineState64, value: u32) void {
        self.fpsr = cleanFloatStatus(value);
    }

    pub fn key(self: *const MachineState64) BlockKey {
        return BlockKey.init(self.pc, self.floatControl());
    }

    pub fn negative(self: *const MachineState64) bool {
        return bits.getBit32(self.nzcv, 31);
    }

    pub fn zero(self: *const MachineState64) bool {
        return bits.getBit32(self.nzcv, 30);
    }

    pub fn carry(self: *const MachineState64) bool {
        return bits.getBit32(self.nzcv, 29);
    }

    pub fn overflow(self: *const MachineState64) bool {
        return bits.getBit32(self.nzcv, 28);
    }

    pub fn readNzcv(self: *const MachineState64) u32 {
        return self.nzcv & 0xf0000000;
    }

    pub fn writeNzcv(self: *MachineState64, value: u32) void {
        self.nzcv = value & 0xf0000000;
    }
};

pub const ImmediateError = error{
    OutOfRange,
};

pub fn Immediate(comptime width: u6) type {
    if (width == 0 or width > 32) {
        @compileError("invalid immediate width");
    }
    return struct {
        value: u32,

        pub const bit_count = width;

        pub fn init(value: u32) ImmediateError!@This() {
            if (width < 32 and (value >> width) != 0) {
                return error.OutOfRange;
            }
            return @This(){ .value = value };
        }

        pub fn zeroExtend(self: @This()) u32 {
            return self.value;
        }

        pub fn signExtend(self: @This()) i32 {
            if (width == 32) {
                return @bitCast(i32, self.value);
            }
            return bits.signExtend32(self.value, @intCast(u5, width));
        }

        pub fn bit(self: @This(), comptime index: u6) bool {
            if (index >= width) {
                @compileError("immediate bit out of range");
            }
            return ((self.value >> index) & 1) != 0;
        }
    };
}

pub fn concatImmediate(comptime left_width: u6, comptime right_width: u6, left: Immediate(left_width), right: Immediate(right_width)) Immediate(left_width + right_width) {
    const combined = (left.zeroExtend() << right_width) | right.zeroExtend();
    return Immediate(left_width + right_width).init(combined) catch unreachable;
}
