const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");
const main = @import("a64_core.zig");
const Core64 = main.Core64;
const Core64Error = main.Core64Error;
const FaultKind64 = main.FaultKind64;
const CacheAction64 = main.CacheAction64;
const FloatNanMode64 = main.FloatNanMode64;
const HostHooks64 = main.HostHooks64;
const a64_flags = @import("a64_math_flags.zig");
const MathResult = a64_flags.MathResult;
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
const a64_memory = @import("a64_memory_bits.zig");
const readLittle64 = a64_memory.readLittle64;
const writeLittle64 = a64_memory.writeLittle64;

pub const Core64Methods = struct {
    pub fn extendedReg(self: *const Core64, wide: bool, reg: a64_state.GeneralReg, option: u3, amount: u3) u64 {
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

    pub fn readSized(self: *const Core64, wide: bool, reg: a64_state.GeneralReg, allow_sp: bool) u64 {
        if (reg == .sp) {
            if (allow_sp) {
                return if (wide) self.state.sp else @as(u64, @intCast(u32, self.state.sp));
            }
            return 0;
        }
        return if (wide) self.state.read(reg) else @as(u64, @intCast(u32, self.state.read(reg)));
    }

    pub fn writeSized(self: *Core64, wide: bool, reg: a64_state.GeneralReg, value: u64, allow_sp: bool) void {
        if (reg == .sp) {
            if (allow_sp) {
                self.state.sp = if (wide) value else @as(u64, @intCast(u32, value));
            }
            return;
        }
        self.state.write(reg, if (wide) value else @as(u64, @intCast(u32, value)));
    }

    pub fn writeNzcv(self: *Core64, wide: bool, result: MathResult) void {
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

    pub fn writeLogicalNzcv(self: *Core64, wide: bool, result: u64) void {
        var nzcv: u32 = 0;
        if (if (wide) ((result & 0x8000000000000000) != 0) else ((result & 0x80000000) != 0)) {
            nzcv |= 0x80000000;
        }
        if (if (wide) result == 0 else @intCast(u32, result) == 0) {
            nzcv |= 0x40000000;
        }
        self.state.writeNzcv(nzcv);
    }

    pub fn readMemory(self: *Core64, address: u64, bytes: usize) Core64Error!u64 {
        if (self.readDirect(address, bytes)) |value| {
            return value;
        }
        switch (bytes) {
            1 => {
                const callback = self.hooks.memory.read8 orelse return error.MissingRead;
                return @as(u64, callback(address, self.hooks.context));
            },
            2 => {
                const callback = self.hooks.memory.read16 orelse return error.MissingRead;
                return @as(u64, callback(address, self.hooks.context));
            },
            4 => {
                const callback = self.hooks.memory.read32 orelse return error.MissingRead;
                return @as(u64, callback(address, self.hooks.context));
            },
            8 => {
                const callback = self.hooks.memory.read64 orelse return error.MissingRead;
                return callback(address, self.hooks.context);
            },
            else => return error.ReservedInstruction,
        }
    }

    pub fn readMemoryVector(self: *Core64, address: u64) Core64Error!a64_state.VectorValue {
        if (self.directPointer(address, 16)) |memory| {
            return a64_state.VectorValue{
                .low = readLittle64(memory, 0),
                .high = readLittle64(memory, 8),
            };
        }
        const callback = self.hooks.memory.read128 orelse return error.MissingRead;
        return callback(address, self.hooks.context);
    }

    pub fn writeMemory(self: *Core64, address: u64, bytes: usize, value: u64) Core64Error!void {
        if (self.writeDirect(address, bytes, value)) {
            return;
        }
        switch (bytes) {
            1 => {
                const callback = self.hooks.memory.write8 orelse return error.MissingWrite;
                callback(address, @intCast(u8, value & 0xff), self.hooks.context);
            },
            2 => {
                const callback = self.hooks.memory.write16 orelse return error.MissingWrite;
                callback(address, @intCast(u16, value & 0xffff), self.hooks.context);
            },
            4 => {
                const callback = self.hooks.memory.write32 orelse return error.MissingWrite;
                callback(address, @intCast(u32, value & 0xffffffff), self.hooks.context);
            },
            8 => {
                const callback = self.hooks.memory.write64 orelse return error.MissingWrite;
                callback(address, value, self.hooks.context);
            },
            else => return error.ReservedInstruction,
        }
    }

    pub fn writeMemoryVector(self: *Core64, address: u64, value: a64_state.VectorValue) Core64Error!void {
        if (self.directPointer(address, 16)) |memory| {
            writeLittle64(memory, 0, value.low);
            writeLittle64(memory, 8, value.high);
            return;
        }
        const callback = self.hooks.memory.write128 orelse return error.MissingWrite;
        callback(address, value, self.hooks.context);
    }

    pub fn directPointer(self: *Core64, address: u64, bytes: usize) ?[*]u8 {
        if (self.bypassDirectForMisalignment(address, bytes)) {
            return null;
        }
        const callback = self.hooks.memory.direct orelse return null;
        return callback(address, bytes, self.hooks.context);
    }

    fn bypassDirectForMisalignment(self: *Core64, address: u64, bytes: usize) bool {
        const bit_size = @intCast(u16, bytes * 8);
        if (bit_size == 8 or (self.hooks.memory.direct_misaligned_bits & bit_size) == 0) {
            return false;
        }

        const align_mask = @as(u64, bytes - 1);
        if ((address & align_mask) == 0) {
            return false;
        }

        if (!self.hooks.memory.direct_boundary_only) {
            return true;
        }

        const page_mask = @as(u64, 4095);
        const page_align_mask = page_mask & ~align_mask;
        return (address & page_align_mask) == page_align_mask;
    }

    pub fn readDirect(self: *Core64, address: u64, bytes: usize) ?u64 {
        const memory = self.directPointer(address, bytes) orelse return null;
        var value: u64 = 0;
        var index: usize = 0;
        while (index < bytes) : (index += 1) {
            value |= @as(u64, memory[index]) << @intCast(u6, index * 8);
        }
        return value;
    }

    pub fn writeDirect(self: *Core64, address: u64, bytes: usize, value: u64) bool {
        const memory = self.directPointer(address, bytes) orelse return false;
        var index: usize = 0;
        while (index < bytes) : (index += 1) {
            memory[index] = @intCast(u8, (value >> @intCast(u6, index * 8)) & 0xff);
        }
        return true;
    }

    pub fn exclusiveHolds(self: *const Core64, address: u64) bool {
        return self.state.exclusive and (((address ^ self.state.exclusive_address) & 0xfffffffffffffff0) == 0);
    }

    pub fn markExclusive(self: *Core64, address: u64, bytes: usize) void {
        self.state.exclusive = true;
        self.state.exclusive_address = address;
        if (self.hooks.shared_reservations) |reservations| {
            reservations.mark(self.hooks.worker_index, address, bytes);
        }
    }

    pub fn claimExclusive(self: *Core64, address: u64, bytes: usize) bool {
        if (!self.exclusiveHolds(address)) {
            return false;
        }
        if (self.hooks.shared_reservations) |reservations| {
            if (!reservations.claim(self.hooks.worker_index, address, bytes)) {
                return false;
            }
        }
        self.state.exclusive = false;
        return true;
    }

    pub fn clearReservation(self: *Core64) void {
        self.state.exclusive = false;
    }

    pub fn conditionHolds(self: *const Core64, code: u4) bool {
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
};
