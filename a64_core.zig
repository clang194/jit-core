const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");

pub const Core64Error = error{
    Busy,
    ReservedInstruction,
    MissingFallback,
};

pub const MemoryHooks64 = struct {
    readCode: ?fn (u64, ?*c_void) u32,
    read8: ?fn (u64, ?*c_void) u8,
    read16: ?fn (u64, ?*c_void) u16,
    read32: ?fn (u64, ?*c_void) u32,
    read64: ?fn (u64, ?*c_void) u64,
    write8: ?fn (u64, u8, ?*c_void) void,
    write16: ?fn (u64, u16, ?*c_void) void,
    write32: ?fn (u64, u32, ?*c_void) void,
    write64: ?fn (u64, u64, ?*c_void) void,
    readOnly: ?fn (u64, ?*c_void) bool,

    pub fn empty() MemoryHooks64 {
        return MemoryHooks64{
            .readCode = null,
            .read8 = null,
            .read16 = null,
            .read32 = null,
            .read64 = null,
            .write8 = null,
            .write16 = null,
            .write32 = null,
            .write64 = null,
            .readOnly = null,
        };
    }
};

pub const HostHooks64 = struct {
    pub const CycleHooks = struct {
        add: ?fn (u64, ?*c_void) void,
        remaining: ?fn (?*c_void) u64,

        pub fn empty() CycleHooks {
            return CycleHooks{
                .add = null,
                .remaining = null,
            };
        }
    };

    memory: MemoryHooks64,
    fallback: ?fn (u64, usize, *a64_state.MachineState64, ?*c_void) void,
    supervisor: ?fn (u32, *a64_state.MachineState64, ?*c_void) void,
    cycles: CycleHooks,
    context: ?*c_void,

    pub fn empty() HostHooks64 {
        return HostHooks64{
            .memory = MemoryHooks64.empty(),
            .fallback = null,
            .supervisor = null,
            .cycles = CycleHooks.empty(),
            .context = null,
        };
    }
};

pub const Core64 = struct {
    state: a64_state.MachineState64,
    hooks: HostHooks64,
    active: bool,
    halt: bool,

    pub fn init(hooks: HostHooks64) Core64 {
        return Core64{
            .state = a64_state.MachineState64.zeroed(),
            .hooks = hooks,
            .active = false,
            .halt = false,
        };
    }

    fn addCycles(self: *Core64, count: u64) void {
        if (self.hooks.cycles.add) |callback| {
            callback(count, self.hooks.context);
        }
    }

    fn hasCycles(self: *Core64, budget: usize, used: usize) bool {
        if (self.hooks.cycles.remaining) |callback| {
            return callback(self.hooks.context) != 0;
        }
        return used < budget;
    }

    pub fn run(self: *Core64, budget: usize) Core64Error!usize {
        if (self.active) {
            return error.Busy;
        }
        self.active = true;
        defer self.active = false;

        self.halt = false;
        var used: usize = 0;
        while (self.hasCycles(budget, used) and !self.halt) {
            try self.runOne();
            used += 1;
            self.addCycles(1);
        }
        return used;
    }

    fn runOne(self: *Core64) Core64Error!void {
        if (self.hooks.memory.readCode) |read_code| {
            const word = read_code(self.state.pc, self.hooks.context);
            if (self.runPcRelative(word)) {
                return;
            }
            if (self.runBranch(word)) {
                return;
            }
            if (self.runCompareBranch(word)) {
                return;
            }
            if (try self.runLogicalImmediate(word)) {
                return;
            }
            if (try self.runLogicalShifted(word)) {
                return;
            }
            if (try self.runAddSubImmediate(word)) {
                return;
            }
            if (try self.runAddShifted(word)) {
                return;
            }
            if (try self.runAddSubExtended(word)) {
                return;
            }
            if (try self.runAddSubCarry(word)) {
                return;
            }
        }
        const callback = self.hooks.fallback orelse return error.MissingFallback;
        callback(self.state.pc, 1, &self.state, self.hooks.context);
    }

    fn runPcRelative(self: *Core64, word: u32) bool {
        if ((word & 0x1f000000) != 0x10000000) {
            return false;
        }

        const page = (word & 0x80000000) != 0;
        const immlo = (word >> 29) & 3;
        const immhi = (word >> 5) & 0x7ffff;
        var immediate = (@as(u64, immhi) << 2) | @as(u64, immlo);
        var base = self.state.pc;
        if (page) {
            immediate <<= 12;
            base &= ~@as(u64, 0xfff);
        }
        self.writeSized(true, regFromWord(word), base +% immediate, false);
        self.state.pc +%= 4;
        return true;
    }

    fn runBranch(self: *Core64, word: u32) bool {
        if ((word & 0xff000010) == 0x54000000) {
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 5) & 0x7ffff) << 2, 21));
            if (self.conditionHolds(@intCast(u4, word & 0xf))) {
                self.state.pc +%= offset;
            } else {
                self.state.pc +%= 4;
            }
            return true;
        }

        if ((word & 0x7c000000) == 0x14000000) {
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, word & 0x03ffffff) << 2, 28));
            if ((word & 0x80000000) != 0) {
                self.state.write(.x30, self.state.pc +% 4);
            }
            self.state.pc +%= offset;
            return true;
        }

        if ((word & 0xfffffc1f) == 0xd61f0000) {
            self.state.pc = self.state.read(regFromWord(word >> 5));
            return true;
        }

        if ((word & 0xfffffc1f) == 0xd63f0000) {
            const target = self.state.read(regFromWord(word >> 5));
            self.state.write(.x30, self.state.pc +% 4);
            self.state.pc = target;
            return true;
        }

        if ((word & 0xfffffc1f) == 0xd65f0000) {
            self.state.pc = self.state.read(regFromWord(word >> 5));
            return true;
        }

        return false;
    }

    fn runCompareBranch(self: *Core64, word: u32) bool {
        if ((word & 0x7e000000) == 0x34000000) {
            const wide = (word & 0x80000000) != 0;
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 5) & 0x7ffff) << 2, 21));
            const value = self.readSized(wide, regFromWord(word), false);
            const want_nonzero = (word & 0x01000000) != 0;
            if ((value != 0) == want_nonzero) {
                self.state.pc +%= offset;
            } else {
                self.state.pc +%= 4;
            }
            return true;
        }

        if ((word & 0x7e000000) == 0x36000000) {
            const bit_index = @intCast(u6, ((word >> 26) & 0x20) | ((word >> 19) & 0x1f));
            const wide = bit_index >= 32;
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 5) & 0x3fff) << 2, 16));
            const value = self.readSized(wide, regFromWord(word), false);
            const bit_set = ((value >> bit_index) & 1) != 0;
            const want_set = (word & 0x01000000) != 0;
            if (bit_set == want_set) {
                self.state.pc +%= offset;
            } else {
                self.state.pc +%= 4;
            }
            return true;
        }

        return false;
    }

    fn runLogicalImmediate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1f800000) != 0x12000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const opcode = @intCast(u2, (word >> 29) & 3);
        const n = (word & 0x00400000) != 0;
        if (!wide and n) {
            return error.ReservedInstruction;
        }
        const immediate = decodeLogicalMask(n, @intCast(u6, (word >> 10) & 0x3f), @intCast(u6, (word >> 16) & 0x3f)) orelse return error.ReservedInstruction;
        const dest = regFromWord(word);
        const left = self.readSized(wide, regFromWord(word >> 5), false);
        const result = logicalOp(wide, opcode, left, immediate, false);
        if (opcode == 3) {
            self.writeLogicalNzcv(wide, result);
            self.writeSized(wide, dest, result, false);
        } else {
            self.writeSized(wide, dest, result, dest == .sp);
        }
        self.state.pc +%= 4;
        return true;
    }

    fn runLogicalShifted(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1f000000) != 0x0a000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const opcode = @intCast(u2, (word >> 29) & 3);
        const invert = (word & 0x00200000) != 0;
        const amount = @intCast(u6, (word >> 10) & 0x3f);
        if (!wide and (amount & 0x20) != 0) {
            return error.ReservedInstruction;
        }

        const left = self.readSized(wide, regFromWord(word >> 5), false);
        const right = self.shiftedReg(wide, regFromWord(word >> 16), @intCast(u2, (word >> 22) & 3), amount);
        const result = logicalOp(wide, opcode, left, right, invert);
        const dest = regFromWord(word);
        if (opcode == 3) {
            self.writeLogicalNzcv(wide, result);
        }
        self.writeSized(wide, dest, result, false);
        self.state.pc +%= 4;
        return true;
    }

    fn runAddSubImmediate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1f000000) != 0x11000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const subtract = (word & 0x40000000) != 0;
        const flags = (word & 0x20000000) != 0;
        const shift = @intCast(u2, (word >> 22) & 3);
        if (shift > 1) {
            return error.ReservedInstruction;
        }

        var immediate = @as(u64, (word >> 10) & 0xfff);
        if (shift == 1) {
            immediate <<= 12;
        }

        const source = regFromWord(word >> 5);
        const dest = regFromWord(word);
        const left = self.readSized(wide, source, true);
        const result = if (subtract) mathSub(wide, left, immediate, true) else mathAdd(wide, left, immediate, false);
        if (flags) {
            self.writeNzcv(wide, result);
            self.writeSized(wide, dest, result.word, false);
        } else {
            self.writeSized(wide, dest, result.word, true);
        }
        self.state.pc +%= 4;
        return true;
    }

    fn runAddShifted(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1f200000) != 0x0b000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const subtract = (word & 0x40000000) != 0;
        const flags = (word & 0x20000000) != 0;
        const shift = @intCast(u2, (word >> 22) & 3);
        const amount = @intCast(u6, (word >> 10) & 0x3f);
        if (shift == 3 or (!wide and (amount & 0x20) != 0)) {
            return error.ReservedInstruction;
        }

        const source = regFromWord(word >> 5);
        const shifted = self.shiftedReg(wide, regFromWord(word >> 16), shift, amount);
        const dest = regFromWord(word);
        const left = self.readSized(wide, source, false);
        const result = if (subtract) mathSub(wide, left, shifted, true) else mathAdd(wide, left, shifted, false);

        if (flags) {
            self.writeNzcv(wide, result);
            self.writeSized(wide, dest, result.word, false);
        } else {
            self.writeSized(wide, dest, result.word, false);
        }
        self.state.pc +%= 4;
        return true;
    }

    fn shiftedReg(self: *const Core64, wide: bool, reg: a64_state.GeneralReg, shift: u2, amount: u6) u64 {
        const value = self.readSized(wide, reg, false);
        if (wide) {
            return shift64(value, shift, amount);
        }
        return @as(u64, shift32(@intCast(u32, value), shift, @intCast(u5, amount)));
    }

    fn runAddSubExtended(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1fe00000) != 0x0b200000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const subtract = (word & 0x40000000) != 0;
        const flags = (word & 0x20000000) != 0;
        const amount = @intCast(u3, (word >> 10) & 7);
        if (amount > 4) {
            return error.ReservedInstruction;
        }

        const source = regFromWord(word >> 5);
        const extended = self.extendedReg(wide, regFromWord(word >> 16), @intCast(u3, (word >> 13) & 7), amount);
        const dest = regFromWord(word);
        const left = self.readSized(wide, source, true);
        const result = if (subtract) mathSub(wide, left, extended, true) else mathAdd(wide, left, extended, false);

        if (flags) {
            self.writeNzcv(wide, result);
        }
        self.writeSized(wide, dest, result.word, !flags or dest == .sp);
        self.state.pc +%= 4;
        return true;
    }

    fn runAddSubCarry(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1fe0fc00) != 0x1a000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const subtract = (word & 0x40000000) != 0;
        const flags = (word & 0x20000000) != 0;
        const left = self.readSized(wide, regFromWord(word >> 5), false);
        const right = self.readSized(wide, regFromWord(word >> 16), false);
        const result = if (subtract) mathSub(wide, left, right, self.state.carry()) else mathAdd(wide, left, right, self.state.carry());
        if (flags) {
            self.writeNzcv(wide, result);
        }
        self.writeSized(wide, regFromWord(word), result.word, false);
        self.state.pc +%= 4;
        return true;
    }

    fn extendedReg(self: *const Core64, wide: bool, reg: a64_state.GeneralReg, option: u3, amount: u3) u64 {
        const value = self.readSized(wide, reg, false);
        var extended: u64 = switch (option) {
            0 => @as(u64, @intCast(u8, value & 0xff)),
            1 => @as(u64, @intCast(u16, value & 0xffff)),
            2 => @as(u64, @intCast(u32, value)),
            3 => value,
            4 => @bitCast(u64, @as(i64, bits.signExtend32(@intCast(u32, value & 0xff), 8))),
            5 => @bitCast(u64, @as(i64, bits.signExtend32(@intCast(u32, value & 0xffff), 16))),
            6 => @bitCast(u64, @as(i64, @bitCast(i32, @intCast(u32, value)))),
            else => value,
        };
        if (!wide) {
            extended = @as(u64, @intCast(u32, extended));
        }
        return extended << @intCast(u6, amount);
    }

    fn readSized(self: *const Core64, wide: bool, reg: a64_state.GeneralReg, allow_sp: bool) u64 {
        if (reg == .sp) {
            if (allow_sp) {
                return if (wide) self.state.sp else @as(u64, @intCast(u32, self.state.sp));
            }
            return 0;
        }
        return if (wide) self.state.read(reg) else @as(u64, @intCast(u32, self.state.read(reg)));
    }

    fn writeSized(self: *Core64, wide: bool, reg: a64_state.GeneralReg, value: u64, allow_sp: bool) void {
        if (reg == .sp) {
            if (allow_sp) {
                self.state.sp = if (wide) value else @as(u64, @intCast(u32, value));
            }
            return;
        }
        self.state.write(reg, if (wide) value else @as(u64, @intCast(u32, value)));
    }

    fn writeNzcv(self: *Core64, wide: bool, result: MathResult) void {
        var nzcv: u32 = 0;
        if (if (wide) ((result.word & 0x8000000000000000) != 0) else ((result.word & 0x80000000) != 0)) {
            nzcv |= 0x80000000;
        }
        if (if (wide) result.word == 0 else @intCast(u32, result.word) == 0) {
            nzcv |= 0x40000000;
        }
        if (result.carry) {
            nzcv |= 0x20000000;
        }
        if (result.overflow) {
            nzcv |= 0x10000000;
        }
        self.state.writeNzcv(nzcv);
    }

    fn writeLogicalNzcv(self: *Core64, wide: bool, result: u64) void {
        var nzcv: u32 = 0;
        if (if (wide) ((result & 0x8000000000000000) != 0) else ((result & 0x80000000) != 0)) {
            nzcv |= 0x80000000;
        }
        if (if (wide) result == 0 else @intCast(u32, result) == 0) {
            nzcv |= 0x40000000;
        }
        self.state.writeNzcv(nzcv);
    }

    fn conditionHolds(self: *const Core64, code: u4) bool {
        const n = self.state.negative();
        const z = self.state.zero();
        const c = self.state.carry();
        const v = self.state.overflow();
        return switch (code) {
            0x0 => z,
            0x1 => !z,
            0x2 => c,
            0x3 => !c,
            0x4 => n,
            0x5 => !n,
            0x6 => v,
            0x7 => !v,
            0x8 => c and !z,
            0x9 => !c or z,
            0xa => n == v,
            0xb => n != v,
            0xc => !z and n == v,
            0xd => z or n != v,
            0xe => true,
            else => false,
        };
    }

    pub fn clearTranslatedState(self: *Core64) void {
        if (self.active) {
            self.halt = true;
        }
    }

    pub fn clearRange(self: *Core64, start: u64, length: usize) void {
        _ = start;
        _ = length;
        if (self.active) {
            self.halt = true;
        }
    }

    pub fn resetState(self: *Core64) Core64Error!void {
        if (self.active) {
            return error.Busy;
        }
        self.state = a64_state.MachineState64.zeroed();
        self.halt = false;
    }

    pub fn requestHalt(self: *Core64) void {
        self.halt = true;
    }

    pub fn isActive(self: *const Core64) bool {
        return self.active;
    }

    pub fn stackPointer(self: *const Core64) u64 {
        return self.state.sp;
    }

    pub fn writeStackPointer(self: *Core64, value: u64) void {
        self.state.sp = value;
    }

    pub fn programCounter(self: *const Core64) u64 {
        return self.state.pc;
    }

    pub fn writeProgramCounter(self: *Core64, value: u64) void {
        self.state.pc = value;
    }

    pub fn readReg(self: *const Core64, reg: a64_state.GeneralReg) u64 {
        return self.state.read(reg);
    }

    pub fn writeReg(self: *Core64, reg: a64_state.GeneralReg, value: u64) void {
        self.state.write(reg, value);
    }

    pub fn regs(self: *Core64) *[31]u64 {
        return &self.state.regs;
    }

    pub fn regsView(self: *const Core64) *const [31]u64 {
        return &self.state.regs;
    }

    pub fn writeRegs(self: *Core64, value: [31]u64) void {
        self.state.regs = value;
    }

    pub fn readVector(self: *const Core64, reg: a64_state.VectorReg) a64_state.VectorValue {
        return self.state.readVector(reg);
    }

    pub fn writeVector(self: *Core64, reg: a64_state.VectorReg, value: a64_state.VectorValue) void {
        self.state.writeVector(reg, value);
    }

    pub fn vectors(self: *Core64) *[32]a64_state.VectorValue {
        return &self.state.vectors;
    }

    pub fn vectorsView(self: *const Core64) *const [32]a64_state.VectorValue {
        return &self.state.vectors;
    }

    pub fn writeVectors(self: *Core64, value: [32]a64_state.VectorValue) void {
        self.state.vectors = value;
    }

    pub fn floatControl(self: *const Core64) u32 {
        return self.state.fpcr;
    }

    pub fn writeFloatControl(self: *Core64, value: u32) void {
        self.state.writeFloatControl(value);
    }

    pub fn status(self: *const Core64) u32 {
        return self.state.readNzcv();
    }

    pub fn writeStatus(self: *Core64, value: u32) void {
        self.state.writeNzcv(value);
    }
};

const MathResult = struct {
    word: u64,
    carry: bool,
    overflow: bool,
};

fn mathAdd(wide: bool, left: u64, right: u64, carry_in: bool) MathResult {
    if (wide) {
        return mathAdd64(left, right, carry_in);
    }
    const result = mathAdd32(@intCast(u32, left), @intCast(u32, right), carry_in);
    return MathResult{
        .word = @as(u64, @intCast(u32, result.word)),
        .carry = result.carry,
        .overflow = result.overflow,
    };
}

fn mathSub(wide: bool, left: u64, right: u64, carry_in: bool) MathResult {
    return mathAdd(wide, left, ~right, carry_in);
}

fn mathAdd32(left: u32, right: u32, carry_in: bool) MathResult {
    const carry: u64 = if (carry_in) 1 else 0;
    const wide = @as(u64, left) + @as(u64, right) + carry;
    const result = @intCast(u32, wide & 0xffffffff);
    const overflow = ((~(left ^ right) & (left ^ result)) & 0x80000000) != 0;
    return MathResult{
        .word = @as(u64, result),
        .carry = wide > 0xffffffff,
        .overflow = overflow,
    };
}

fn mathAdd64(left: u64, right: u64, carry_in: bool) MathResult {
    const carry: u128 = if (carry_in) 1 else 0;
    const wide = @as(u128, left) + @as(u128, right) + carry;
    const result = @intCast(u64, wide & 0xffffffffffffffff);
    const overflow = ((~(left ^ right) & (left ^ result)) & 0x8000000000000000) != 0;
    return MathResult{
        .word = result,
        .carry = wide > 0xffffffffffffffff,
        .overflow = overflow,
    };
}

fn logicalOp(wide: bool, opcode: u2, left: u64, right: u64, invert: bool) u64 {
    const operand = if (invert) ~right else right;
    const result = switch (opcode) {
        0, 3 => left & operand,
        1 => left | operand,
        else => left ^ operand,
    };
    if (wide) {
        return result;
    }
    return @as(u64, @intCast(u32, result));
}

fn decodeLogicalMask(n: bool, imms: u6, immr: u6) ?u64 {
    const marker = (if (n) @as(u64, 1) << 6 else @as(u64, 0)) | @as(u64, imms ^ 0x3f);
    const len = highestSetBit(marker);
    if (len < 1) {
        return null;
    }

    const levels = ones(@intCast(u6, len));
    if ((@as(u64, imms) & levels) == levels) {
        return null;
    }

    const s = @as(u64, imms) & levels;
    const r = @as(u64, immr) & levels;
    const size = @as(u6, 1) << @intCast(u3, len);
    const element = ones(@intCast(u6, s + 1));
    return rotateRight64(replicate64(element, size), @intCast(u6, r));
}

fn highestSetBit(value: u64) i8 {
    var remaining = value;
    var result: i8 = -1;
    while (remaining != 0) {
        remaining >>= 1;
        result += 1;
    }
    return result;
}

fn ones(count: u6) u64 {
    if (count == 64) {
        return ~@as(u64, 0);
    }
    return (@as(u64, 1) << count) - 1;
}

fn replicate64(value: u64, element_size: u6) u64 {
    var result = value & ones(element_size);
    var size = element_size;
    while (size < 64) {
        result |= result << size;
        size *= 2;
    }
    return result;
}

fn rotateRight64(value: u64, amount: u6) u64 {
    const shift = amount & 63;
    if (shift == 0) {
        return value;
    }
    return (value >> shift) | (value << @intCast(u6, 64 - shift));
}

fn regFromWord(value: u32) a64_state.GeneralReg {
    return @intToEnum(a64_state.GeneralReg, @intCast(u5, value & 0x1f));
}

fn shift32(value: u32, shift: u2, amount: u5) u32 {
    switch (shift) {
        0 => return value << amount,
        1 => return value >> amount,
        2 => return @bitCast(u32, @bitCast(i32, value) >> amount),
        else => return rotateRight32(value, amount),
    }
}

fn shift64(value: u64, shift: u2, amount: u6) u64 {
    switch (shift) {
        0 => return value << amount,
        1 => return value >> amount,
        2 => return @bitCast(u64, @bitCast(i64, value) >> amount),
        else => return rotateRight64(value, amount),
    }
}

fn rotateRight32(value: u32, amount: u5) u32 {
    const shift = amount & 31;
    if (shift == 0) {
        return value;
    }
    return (value >> shift) | (value << @intCast(u5, 32 - shift));
}
