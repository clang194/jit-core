const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const Core64 = main.Core64;
const Core64Error = main.Core64Error;
const FaultKind64 = main.FaultKind64;
const CacheAction64 = main.CacheAction64;
const FloatNanMode64 = main.FloatNanMode64;
const HostHooks64 = main.HostHooks64;
usingnamespace @import("a64_math_flags.zig");
usingnamespace @import("a64_logic_masks.zig");
usingnamespace @import("a64_immediate_vectors.zig");
usingnamespace @import("a64_divide_crc.zig");
usingnamespace @import("a64_crypto_tables.zig");
usingnamespace @import("a64_float_control.zig");
usingnamespace @import("a64_float_arithmetic.zig");
usingnamespace @import("a64_float_minmax.zig");
usingnamespace @import("a64_float_nan.zig");
usingnamespace @import("a64_vector_access.zig");
usingnamespace @import("a64_crypto_vectors.zig");
usingnamespace @import("a64_vector_integer.zig");
usingnamespace @import("a64_vector_float.zig");
usingnamespace @import("a64_vector_compare.zig");
usingnamespace @import("a64_vector_shift.zig");
usingnamespace @import("a64_count_bits.zig");
usingnamespace @import("a64_memory_bits.zig");

pub const Core64Methods = struct {
    pub fn init(hooks: HostHooks64) Core64 {
        return Core64{
            .state = a64_state.MachineState64.zeroed(),
            .hooks = hooks,
            .active = false,
            .halt = false,
        };
    }

    pub fn addCycles(self: *Core64, count: u64) void {
        if (self.hooks.cycles.add) |callback| {
            callback(count, self.hooks.context);
        }
    }

    pub fn hasCycles(self: *Core64, budget: usize, used: usize) bool {
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

    pub fn step(self: *Core64) Core64Error!void {
        if (self.active) {
            return error.Busy;
        }
        self.active = true;
        defer self.active = false;

        self.halt = true;
        try self.runOne();
        self.addCycles(1);
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

    pub fn floatStatus(self: *const Core64) u32 {
        return self.state.floatStatus();
    }

    pub fn writeFloatStatus(self: *Core64, value: u32) void {
        self.state.writeFloatStatus(value);
    }

    pub fn status(self: *const Core64) u32 {
        return self.state.readNzcv();
    }

    pub fn writeStatus(self: *Core64, value: u32) void {
        self.state.writeNzcv(value);
    }
};
