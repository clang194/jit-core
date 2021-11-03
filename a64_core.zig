const a64_state = @import("a64_state.zig");

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
            if (try self.runAddShifted(word)) {
                return;
            }
        }
        const callback = self.hooks.fallback orelse return error.MissingFallback;
        callback(self.state.pc, 1, &self.state, self.hooks.context);
    }

    fn runAddShifted(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x7f200000) != 0x0b000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const shift = @intCast(u2, (word >> 22) & 3);
        const amount = @intCast(u6, (word >> 10) & 0x3f);
        if (shift == 3 or (!wide and (amount & 0x20) != 0)) {
            return error.ReservedInstruction;
        }

        const source = regFromWord(word >> 5);
        const shifted = self.shiftedReg(wide, regFromWord(word >> 16), shift, amount);
        const dest = regFromWord(word);

        if (wide) {
            self.state.write(dest, self.state.read(source) +% shifted);
        } else {
            const result = @intCast(u32, self.state.read(source)) +% @intCast(u32, shifted);
            self.state.write(dest, @as(u64, result));
        }
        self.state.pc +%= 4;
        return true;
    }

    fn shiftedReg(self: *const Core64, wide: bool, reg: a64_state.GeneralReg, shift: u2, amount: u6) u64 {
        const value = self.state.read(reg);
        if (wide) {
            return shift64(value, shift, amount);
        }
        return @as(u64, shift32(@intCast(u32, value), shift, @intCast(u5, amount)));
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

    pub fn readVector(self: *const Core64, reg: a64_state.VectorReg) a64_state.VectorValue {
        return self.state.readVector(reg);
    }

    pub fn writeVector(self: *Core64, reg: a64_state.VectorReg, value: a64_state.VectorValue) void {
        self.state.writeVector(reg, value);
    }

    pub fn floatControl(self: *const Core64) u32 {
        return self.state.fpcr;
    }

    pub fn writeFloatControl(self: *Core64, value: u32) void {
        self.state.writeFloatControl(value);
    }
};

fn regFromWord(value: u32) a64_state.GeneralReg {
    return @intToEnum(a64_state.GeneralReg, @intCast(u5, value & 0x1f));
}

fn shift32(value: u32, shift: u2, amount: u5) u32 {
    switch (shift) {
        0 => return value << amount,
        1 => return value >> amount,
        2 => return @bitCast(u32, @bitCast(i32, value) >> amount),
        else => return value,
    }
}

fn shift64(value: u64, shift: u2, amount: u6) u64 {
    switch (shift) {
        0 => return value << amount,
        1 => return value >> amount,
        2 => return @bitCast(u64, @bitCast(i64, value) >> amount),
        else => return value,
    }
}
