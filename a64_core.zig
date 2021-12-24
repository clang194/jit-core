const a64_state = @import("a64_state.zig");
const bits = @import("bits.zig");

pub const Core64Error = error{
    Busy,
    UnallocatedEncoding,
    ReservedInstruction,
    Unpredictable,
    MissingRead,
    MissingWrite,
    MissingFallback,
};

pub const FaultKind64 = enum {
    unallocated_encoding,
    reserved_value,
    unpredictable_instruction,
};

pub const MemoryHooks64 = struct {
    readCode: ?fn (u64, ?*c_void) u32,
    read8: ?fn (u64, ?*c_void) u8,
    read16: ?fn (u64, ?*c_void) u16,
    read32: ?fn (u64, ?*c_void) u32,
    read64: ?fn (u64, ?*c_void) u64,
    read128: ?fn (u64, ?*c_void) a64_state.VectorValue,
    write8: ?fn (u64, u8, ?*c_void) void,
    write16: ?fn (u64, u16, ?*c_void) void,
    write32: ?fn (u64, u32, ?*c_void) void,
    write64: ?fn (u64, u64, ?*c_void) void,
    write128: ?fn (u64, a64_state.VectorValue, ?*c_void) void,
    readOnly: ?fn (u64, ?*c_void) bool,

    pub fn empty() MemoryHooks64 {
        return MemoryHooks64{
            .readCode = null,
            .read8 = null,
            .read16 = null,
            .read32 = null,
            .read64 = null,
            .read128 = null,
            .write8 = null,
            .write16 = null,
            .write32 = null,
            .write64 = null,
            .write128 = null,
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
    exception: ?fn (u64, FaultKind64, ?*c_void) void,
    cycles: CycleHooks,
    context: ?*c_void,

    pub fn empty() HostHooks64 {
        return HostHooks64{
            .memory = MemoryHooks64.empty(),
            .fallback = null,
            .supervisor = null,
            .exception = null,
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
            if (self.runSupervisorCall(word)) {
                return;
            }
            const load_store = self.runLoadStore(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (load_store) {
                return;
            }
            const pair_load_store = self.runPairLoadStore(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (pair_load_store) {
                return;
            }
            const vector_pair_load_store = self.runVectorPairLoadStore(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_pair_load_store) {
                return;
            }
            const vector_structure_transfer = self.runVectorStructureTransfer(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_structure_transfer) {
                return;
            }
            const logical_immediate = self.runLogicalImmediate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (logical_immediate) {
                return;
            }
            const logical_shifted = self.runLogicalShifted(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (logical_shifted) {
                return;
            }
            const add_sub_immediate = self.runAddSubImmediate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (add_sub_immediate) {
                return;
            }
            const add_shifted = self.runAddShifted(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (add_shifted) {
                return;
            }
            const add_sub_extended = self.runAddSubExtended(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (add_sub_extended) {
                return;
            }
            const add_sub_carry = self.runAddSubCarry(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (add_sub_carry) {
                return;
            }
            const wide_move = self.runWideMove(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (wide_move) {
                return;
            }
            const bitfield_move = self.runBitfieldMove(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (bitfield_move) {
                return;
            }
            const extract_register = self.runExtractRegister(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (extract_register) {
                return;
            }
            if (self.runConditionalSelect(word)) {
                return;
            }
            const byte_reverse = self.runByteReverse(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (byte_reverse) {
                return;
            }
            const float_immediate = self.runFloatImmediate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (float_immediate) {
                return;
            }
            const float_convert = self.runFloatConvert(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (float_convert) {
                return;
            }
            const float_binary = self.runFloatBinary(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (float_binary) {
                return;
            }
            const float_compare = self.runFloatCompare(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (float_compare) {
                return;
            }
            if (self.runAesMix(word)) {
                return;
            }
            const vector_duplicate = self.runVectorDuplicate(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_duplicate) {
                return;
            }
            const vector_extract = self.runVectorExtractToRegister(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_extract) {
                return;
            }
            const vector_add = self.runVectorAdd(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_add) {
                return;
            }
            const vector_pair_add = self.runVectorPairAdd(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_pair_add) {
                return;
            }
            const vector_equal = self.runVectorEqual(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (vector_equal) {
                return;
            }
            if (self.runVectorAnd(word)) {
                return;
            }
            if (self.runDivide(word)) {
                return;
            }
            const crc = self.runCrc(word) catch |err| {
                try self.raiseFault(err);
                return;
            };
            if (crc) {
                return;
            }
            if (self.runVariableShift(word)) {
                return;
            }
            if (self.runSystemHint(word)) {
                return;
            }
            if (self.runLeadingZeroCount(word)) {
                return;
            }
            if (self.runMultiplyAdd(word)) {
                return;
            }
            if (self.runLongMultiplyAdd(word)) {
                return;
            }
        }
        const callback = self.hooks.fallback orelse return error.MissingFallback;
        callback(self.state.pc, 1, &self.state, self.hooks.context);
    }

    fn raiseFault(self: *Core64, err: Core64Error) Core64Error!void {
        const kind = switch (err) {
            error.UnallocatedEncoding => FaultKind64.unallocated_encoding,
            error.ReservedInstruction => FaultKind64.reserved_value,
            error.Unpredictable => FaultKind64.unpredictable_instruction,
            else => return err,
        };
        const callback = self.hooks.exception orelse return err;
        callback(self.state.pc, kind, self.hooks.context);
    }

    fn runPcRelative(self: *Core64, word: u32) bool {
        if ((word & 0x1f000000) != 0x10000000) {
            return false;
        }

        const page = (word & 0x80000000) != 0;
        const immlo = (word >> 29) & 3;
        const immhi = (word >> 5) & 0x7ffff;
        const raw = (@as(u64, immhi) << 2) | @as(u64, immlo);
        const signed = bits.signExtend64(raw, 21);
        var immediate = @bitCast(u64, signed);
        var base = self.state.pc;
        if (page) {
            immediate = @bitCast(u64, signed << 12);
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

    fn runSupervisorCall(self: *Core64, word: u32) bool {
        if ((word & 0xffe0001f) != 0xd4000001) {
            return false;
        }
        const callback = self.hooks.supervisor orelse return false;
        self.state.pc +%= 4;
        callback((word >> 5) & 0xffff, &self.state, self.hooks.context);
        return true;
    }

    fn runLoadStore(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x3f000000) == 0x18000000) {
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 5) & 0x7ffff) << 2, 21));
            const address = self.state.pc +% offset;
            const value = try self.readMemory(address, if ((word & 0x40000000) != 0) 8 else 4);
            self.writeSized((word & 0x40000000) != 0, regFromWord(word), value, false);
            self.state.pc +%= 4;
            return true;
        }

        if ((word & 0xff000000) == 0x98000000) {
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 5) & 0x7ffff) << 2, 21));
            const address = self.state.pc +% offset;
            const value = @bitCast(u64, bits.signExtend64(try self.readMemory(address, 4), 32));
            self.writeSized(true, regFromWord(word), value, false);
            self.state.pc +%= 4;
            return true;
        }

        if ((word & 0xff000000) == 0xd8000000) {
            self.state.pc +%= 4;
            return true;
        }

        if ((word & 0x3f200400) == 0x3c000400) {
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 12) & 0x1ff), 9));
            return try self.runVectorLoadStoreRegister(word, offset, true, ((word >> 11) & 1) == 0);
        }

        if ((word & 0x3f000000) == 0x3d000000) {
            const scale = @intCast(u3, ((word >> 30) & 3) | (((word >> 23) & 1) << 2));
            const offset = @as(u64, (word >> 10) & 0xfff) << scale;
            return try self.runVectorLoadStoreRegister(word, offset, false, false);
        }

        if ((word & 0x3f200c00) == 0x3c000000) {
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 12) & 0x1ff), 9));
            return try self.runVectorLoadStoreRegister(word, offset, false, false);
        }

        if ((word & 0x3f200c00) == 0x38000800) {
            return try self.runLoadStoreUnprivileged(word);
        }

        if ((word & 0x3f200c00) == 0x38000000) {
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 12) & 0x1ff), 9));
            return try self.runLoadStoreRegister(word, offset, false, false);
        }

        if ((word & 0x3f200400) == 0x38000400) {
            const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 12) & 0x1ff), 9));
            return try self.runLoadStoreRegister(word, offset, true, ((word >> 11) & 1) == 0);
        }

        if ((word & 0x3f000000) == 0x39000000) {
            const size = @intCast(u2, word >> 30);
            const offset = @as(u64, (word >> 10) & 0xfff) << @intCast(u6, size);
            return try self.runLoadStoreRegister(word, offset, false, false);
        }

        return false;
    }

    fn runLoadStoreRegister(self: *Core64, word: u32, offset: u64, writeback: bool, postindex: bool) Core64Error!bool {
        const size = @intCast(u2, word >> 30);
        const opcode = @intCast(u2, (word >> 22) & 3);
        const base_reg = regFromWord(word >> 5);
        const data_reg = regFromWord(word);
        const bytes = @as(usize, 1) << size;

        if ((opcode & 2) != 0 and size == 3) {
            if ((opcode & 1) != 0) {
                return error.ReservedInstruction;
            }
            self.state.pc +%= 4;
            return true;
        }
        if ((opcode & 2) != 0 and size == 2 and (opcode & 1) != 0) {
            return error.ReservedInstruction;
        }
        if (writeback and base_reg == data_reg and base_reg != .sp) {
            return error.Unpredictable;
        }

        var address = self.readSized(true, base_reg, true);
        if (!postindex) {
            address +%= offset;
        }

        if ((opcode & 2) == 0) {
            if ((opcode & 1) == 0) {
                try self.writeMemory(address, bytes, self.readSized(size == 3, data_reg, false));
            } else {
                const value = try self.readMemory(address, bytes);
                self.writeSized(size == 3, data_reg, value, false);
            }
        } else {
            const value = try self.readMemory(address, bytes);
            const extended = @bitCast(u64, bits.signExtend64(value, @intCast(u6, bytes * 8)));
            self.writeSized((opcode & 1) == 0, data_reg, extended, false);
        }

        if (writeback) {
            if (postindex) {
                address +%= offset;
            }
            self.writeSized(true, base_reg, address, true);
        }
        self.state.pc +%= 4;
        return true;
    }

    fn runLoadStoreUnprivileged(self: *Core64, word: u32) Core64Error!bool {
        const size = @intCast(u2, word >> 30);
        const opcode = @intCast(u2, (word >> 22) & 3);
        const base_reg = regFromWord(word >> 5);
        const data_reg = regFromWord(word);
        const bytes = @as(usize, 1) << size;
        const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 12) & 0x1ff), 9));
        const address = self.readSized(true, base_reg, true) +% offset;

        if ((opcode & 2) == 0) {
            if ((opcode & 1) == 0) {
                try self.writeMemory(address, bytes, self.readSized(size == 3, data_reg, false));
            } else {
                const value = try self.readMemory(address, bytes);
                self.writeSized(size == 3, data_reg, value, false);
            }
        } else {
            if (size == 3 or (size == 2 and (opcode & 1) != 0)) {
                return error.UnallocatedEncoding;
            }

            const value = try self.readMemory(address, bytes);
            const extended = @bitCast(u64, bits.signExtend64(value, @intCast(u6, bytes * 8)));
            self.writeSized((opcode & 1) == 0, data_reg, extended, false);
        }

        self.state.pc +%= 4;
        return true;
    }

    fn runVectorLoadStoreRegister(self: *Core64, word: u32, offset: u64, writeback: bool, postindex: bool) Core64Error!bool {
        const scale = @intCast(u3, ((word >> 30) & 3) | (((word >> 23) & 1) << 2));
        if (scale > 4) {
            return error.UnallocatedEncoding;
        }

        const base_reg = regFromWord(word >> 5);
        const data_reg = vectorRegFromWord(word);
        const load = ((word >> 22) & 1) != 0;
        const bytes = @as(usize, 1) << scale;

        var address = self.readSized(true, base_reg, true);
        if (!postindex) {
            address +%= offset;
        }

        if (load) {
            const value = if (bytes == 16)
                try self.readMemoryVector(address)
            else
                a64_state.VectorValue{
                    .low = try self.readMemory(address, bytes),
                    .high = 0,
                };
            self.state.writeVector(data_reg, value);
        } else {
            const value = self.state.readVector(data_reg);
            if (bytes == 16) {
                try self.writeMemoryVector(address, value);
            } else {
                try self.writeMemory(address, bytes, value.low);
            }
        }

        if (writeback) {
            if (postindex) {
                address +%= offset;
            }
            self.writeSized(true, base_reg, address, true);
        }
        self.state.pc +%= 4;
        return true;
    }

    fn runPairLoadStore(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x3e000000) != 0x28000000) {
            return false;
        }

        const opcode = @intCast(u2, word >> 30);
        const not_postindex = ((word >> 24) & 1) != 0;
        const writeback = ((word >> 23) & 1) != 0;
        const load = ((word >> 22) & 1) != 0;
        if (!not_postindex and !writeback) {
            return error.UnallocatedEncoding;
        }
        if ((!load and (opcode & 1) != 0) or opcode == 3) {
            return error.UnallocatedEncoding;
        }

        const signed_load = (opcode & 1) != 0;
        const bytes = if ((opcode & 2) != 0) @as(usize, 8) else @as(usize, 4);
        const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 15) & 0x7f), 7)) << @intCast(u6, if (bytes == 8) 3 else 2);
        const first = regFromWord(word);
        const base_reg = regFromWord(word >> 5);
        const second = regFromWord(word >> 10);

        if (load and first == second) {
            return error.Unpredictable;
        }
        if (writeback and base_reg != .sp and (base_reg == first or base_reg == second)) {
            return error.Unpredictable;
        }

        var address = self.readSized(true, base_reg, true);
        const postindex = !not_postindex;
        if (!postindex) {
            address +%= offset;
        }

        if (load) {
            const low = try self.readMemory(address, bytes);
            const high = try self.readMemory(address +% @intCast(u64, bytes), bytes);
            if (signed_load) {
                self.writeSized(true, first, @bitCast(u64, bits.signExtend64(low, 32)), false);
                self.writeSized(true, second, @bitCast(u64, bits.signExtend64(high, 32)), false);
            } else {
                self.writeSized(bytes == 8, first, low, false);
                self.writeSized(bytes == 8, second, high, false);
            }
        } else {
            try self.writeMemory(address, bytes, self.readSized(bytes == 8, first, false));
            try self.writeMemory(address +% @intCast(u64, bytes), bytes, self.readSized(bytes == 8, second, false));
        }

        if (writeback) {
            if (postindex) {
                address +%= offset;
            }
            self.writeSized(true, base_reg, address, true);
        }
        self.state.pc +%= 4;
        return true;
    }

    fn runVectorPairLoadStore(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x3e000000) != 0x2c000000) {
            return false;
        }

        const opcode = @intCast(u2, word >> 30);
        const not_postindex = ((word >> 24) & 1) != 0;
        const writeback = ((word >> 23) & 1) != 0;
        const load = ((word >> 22) & 1) != 0;
        if (!not_postindex and !writeback) {
            return error.UnallocatedEncoding;
        }
        if (opcode == 3) {
            return error.UnallocatedEncoding;
        }

        const bytes = @as(usize, 4) << opcode;
        const offset = @bitCast(u64, bits.signExtend64(@as(u64, (word >> 15) & 0x7f), 7)) << @intCast(u6, 2 + opcode);
        const first = vectorRegFromWord(word);
        const base_reg = regFromWord(word >> 5);
        const second = vectorRegFromWord(word >> 10);

        if (load and first == second) {
            return error.Unpredictable;
        }

        var address = self.readSized(true, base_reg, true);
        const postindex = !not_postindex;
        if (!postindex) {
            address +%= offset;
        }

        if (load) {
            const low = try self.readVectorPairMemory(address, bytes);
            const high = try self.readVectorPairMemory(address +% @intCast(u64, bytes), bytes);
            self.state.writeVector(first, low);
            self.state.writeVector(second, high);
        } else {
            try self.writeVectorPairMemory(address, bytes, self.state.readVector(first));
            try self.writeVectorPairMemory(address +% @intCast(u64, bytes), bytes, self.state.readVector(second));
        }

        if (writeback) {
            if (postindex) {
                address +%= offset;
            }
            self.writeSized(true, base_reg, address, true);
        }
        self.state.pc +%= 4;
        return true;
    }

    fn runVectorStructureTransfer(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x3f000000) != 0x0c000000 or (word & 0x00200000) != 0) {
            return false;
        }

        const writeback = (word & 0x00800000) != 0;
        const load = (word & 0x00400000) != 0;
        const offset_reg_bits = (word >> 16) & 0x1f;
        if (!writeback and offset_reg_bits != 0) {
            return false;
        }

        const op = @intCast(u4, (word >> 12) & 0xf);
        var repeat: usize = undefined;
        var fields: usize = undefined;
        switch (op) {
            0x0 => {
                repeat = 1;
                fields = 4;
            },
            0x2 => {
                repeat = 4;
                fields = 1;
            },
            0x4 => {
                repeat = 1;
                fields = 3;
            },
            0x6 => {
                repeat = 3;
                fields = 1;
            },
            0x7 => {
                repeat = 1;
                fields = 1;
            },
            0x8 => {
                repeat = 1;
                fields = 2;
            },
            0xa => {
                repeat = 2;
                fields = 1;
            },
            else => return error.UnallocatedEncoding,
        }

        const full = (word & 0x40000000) != 0;
        const lane_bytes = @as(usize, 1) << @intCast(u3, (word >> 10) & 3);
        if (lane_bytes == 8 and !full and fields != 1) {
            return error.ReservedInstruction;
        }
        const lanes = if (full) 16 / lane_bytes else 8 / lane_bytes;

        const base_reg = regFromWord(word >> 5);
        const first_reg = @enumToInt(vectorRegFromWord(word));
        const start_address = self.readSized(true, base_reg, true);
        var offset: u64 = 0;
        var r: usize = 0;
        while (r < repeat) : (r += 1) {
            var lane: usize = 0;
            while (lane < lanes) : (lane += 1) {
                var field: usize = 0;
                while (field < fields) : (field += 1) {
                    const reg = @intToEnum(a64_state.VectorReg, @intCast(u5, (first_reg + r + field) & 31));
                    const address = start_address +% offset;
                    if (load) {
                        var vector = self.state.readVector(reg);
                        if (!full) {
                            vector.high = 0;
                        }
                        setVectorElement(&vector, lane, lane_bytes, try self.readMemory(address, lane_bytes));
                        if (!full) {
                            vector.high = 0;
                        }
                        self.state.writeVector(reg, vector);
                    } else {
                        const vector = self.state.readVector(reg);
                        try self.writeMemory(address, lane_bytes, vectorElement(vector, lane, lane_bytes));
                    }
                    offset += @intCast(u64, lane_bytes);
                }
            }
        }

        if (writeback) {
            const offset_reg = regFromWord(word >> 16);
            const advance = if (offset_reg == .sp) offset else self.readSized(true, offset_reg, false);
            self.writeSized(true, base_reg, start_address +% advance, true);
        }

        self.state.pc +%= 4;
        return true;
    }

    fn readVectorPairMemory(self: *Core64, address: u64, bytes: usize) Core64Error!a64_state.VectorValue {
        if (bytes == 16) {
            return try self.readMemoryVector(address);
        }
        return a64_state.VectorValue{
            .low = try self.readMemory(address, bytes),
            .high = 0,
        };
    }

    fn writeVectorPairMemory(self: *Core64, address: u64, bytes: usize, value: a64_state.VectorValue) Core64Error!void {
        if (bytes == 16) {
            try self.writeMemoryVector(address, value);
            return;
        }
        try self.writeMemory(address, bytes, value.low);
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
            self.writeSized(wide, dest, result.word, false);
        } else {
            self.writeSized(wide, dest, result.word, true);
        }
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

    fn runWideMove(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1f800000) != 0x12800000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const opcode = @intCast(u2, (word >> 29) & 3);
        if (opcode == 1) {
            return error.UnallocatedEncoding;
        }

        const half = @intCast(u2, (word >> 21) & 3);
        if (!wide and (half & 2) != 0) {
            return error.UnallocatedEncoding;
        }

        const shift = @as(u6, half) * 16;
        const dest = regFromWord(word);
        const value = @as(u64, (word >> 5) & 0xffff) << shift;
        const mask = @as(u64, 0xffff) << shift;
        const result = switch (opcode) {
            0 => ~value,
            2 => value,
            else => (self.readSized(wide, dest, false) & ~mask) | value,
        };
        self.writeSized(wide, dest, result, false);
        self.state.pc +%= 4;
        return true;
    }

    fn runBitfieldMove(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x1f800000) != 0x13000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const opcode = @intCast(u2, (word >> 29) & 3);
        if (opcode == 3) {
            return error.UnallocatedEncoding;
        }

        const n = (word & 0x00400000) != 0;
        const rotate = @intCast(u6, (word >> 16) & 0x3f);
        const last = @intCast(u6, (word >> 10) & 0x3f);
        if ((wide and !n) or (!wide and (n or (rotate & 0x20) != 0 or (last & 0x20) != 0))) {
            return error.ReservedInstruction;
        }

        const masks = decodeBitPattern(n, last, rotate, false) orelse return error.ReservedInstruction;
        const source = self.readSized(wide, regFromWord(word >> 5), false);
        const rotated = rotateRightSized(wide, source, rotate);
        const dest = regFromWord(word);
        const result = switch (opcode) {
            0 => blk: {
                const fill = if (((source >> last) & 1) != 0) ~@as(u64, 0) else @as(u64, 0);
                break :blk (fill & ~masks.limit) | (rotated & masks.write & masks.limit);
            },
            1 => blk: {
                const prior = self.readSized(wide, dest, false);
                const bottom = (prior & ~masks.write) | (rotated & masks.write);
                break :blk (prior & ~masks.limit) | (bottom & masks.limit);
            },
            else => rotated & masks.write & masks.limit,
        };
        self.writeSized(wide, dest, result, false);
        self.state.pc +%= 4;
        return true;
    }

    fn runExtractRegister(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0x7fa00000) != 0x13800000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const n = (word & 0x00400000) != 0;
        if (n != wide) {
            return error.UnallocatedEncoding;
        }

        const amount = @intCast(u6, (word >> 10) & 0x3f);
        if (!wide and (amount & 0x20) != 0) {
            return error.ReservedInstruction;
        }

        const lower = self.readSized(wide, regFromWord(word >> 16), false);
        const upper = self.readSized(wide, regFromWord(word >> 5), false);
        self.writeSized(wide, regFromWord(word), extractRegisterBits(wide, lower, upper, amount), false);
        self.state.pc +%= 4;
        return true;
    }

    fn runConditionalSelect(self: *Core64, word: u32) bool {
        if ((word & 0x3fe00800) != 0x1a800000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const fallback = self.readSized(wide, regFromWord(word >> 16), false);
        const altered = switch (@intCast(u2, ((word >> 29) & 2) | ((word >> 10) & 1))) {
            0 => fallback,
            1 => fallback +% 1,
            2 => ~fallback,
            else => ~fallback +% 1,
        };
        const value = if (self.conditionHolds(@intCast(u4, (word >> 12) & 0xf)))
            self.readSized(wide, regFromWord(word >> 5), false)
        else
            altered;
        self.writeSized(wide, regFromWord(word), value, false);
        self.state.pc +%= 4;
        return true;
    }

    fn runByteReverse(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xfffffc00;
        const wide = (word & 0x80000000) != 0;
        const source = self.readSized(wide, regFromWord(word >> 5), false);
        const result = if ((masked & 0x7fffffff) == 0x5ac00000)
            if (wide) reverseBits64(source) else @as(u64, reverseBits32(@intCast(u32, source)))
        else if ((masked & 0x7fffffff) == 0x5ac00400)
            reverseHalfBytes(source)
        else if (masked == 0xdac00800)
            (@as(u64, reverseBytes32(@intCast(u32, source >> 32))) << 32) | @as(u64, reverseBytes32(@intCast(u32, source)))
        else if (masked == 0x5ac00800)
            @as(u64, reverseBytes32(@intCast(u32, source)))
        else if (masked == 0xdac00c00)
            reverseBytes64(source)
        else if (masked == 0x5ac00c00)
            return error.UnallocatedEncoding
        else
            return false;
        self.writeSized(wide, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }

    fn runFloatImmediate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xff201fe0) != 0x1e201000) {
            return false;
        }

        const mode = @intCast(u2, (word >> 22) & 3);
        const encoded = @intCast(u8, (word >> 13) & 0xff);
        const value = switch (mode) {
            0 => @as(u64, expandFloatConstant32(encoded)),
            1 => expandFloatConstant64(encoded),
            3 => @as(u64, expandFloatConstant16(encoded)),
            else => return error.UnallocatedEncoding,
        };
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = value, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    fn runFloatConvert(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xff3e7c00) != 0x1e224000) {
            return false;
        }

        const source_mode = @intCast(u2, (word >> 22) & 3);
        const target_mode = @intCast(u2, (word >> 15) & 3);
        if (source_mode == 2 or target_mode == 2 or source_mode == target_mode) {
            return error.UnallocatedEncoding;
        }
        if (source_mode == 3 or target_mode == 3) {
            return false;
        }

        const control = self.state.floatControl();
        const source = self.state.readVector(vectorRegFromWord(word >> 5));
        const value = if (source_mode == 0)
            float32To64(control, @intCast(u32, source.low))
        else
            @as(u64, float64To32(control, source.low));
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = value, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    fn runFloatBinary(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff20fc00;
        if (masked != 0x1e200800 and masked != 0x1e201800 and masked != 0x1e202800 and masked != 0x1e203800 and masked != 0x1e208800) {
            return false;
        }

        const mode = (word >> 22) & 3;
        if (mode > 1) {
            return error.UnallocatedEncoding;
        }

        const double = mode == 1;
        const control = self.state.floatControl();
        const left = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, if (double) @as(usize, 8) else @as(usize, 4));
        const right = vectorElement(self.state.readVector(vectorRegFromWord(word >> 16)), 0, if (double) @as(usize, 8) else @as(usize, 4));
        const result = switch (masked) {
            0x1e200800 => floatMul(control, double, left, right),
            0x1e201800 => floatDiv(control, double, left, right),
            0x1e202800 => floatAdd(control, double, left, right),
            0x1e203800 => floatSub(control, double, left, right),
            else => negateFloat(double, floatMul(control, double, left, right)),
        };
        self.state.writeVector(vectorRegFromWord(word), a64_state.VectorValue{ .low = result, .high = 0 });
        self.state.pc +%= 4;
        return true;
    }

    fn runFloatCompare(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0xff20fc17;
        if (masked != 0x1e202000 and masked != 0x1e202010) {
            return false;
        }

        const mode = (word >> 22) & 3;
        if (mode > 1) {
            return error.UnallocatedEncoding;
        }

        const double = mode == 1;
        const bytes = if (double) @as(usize, 8) else @as(usize, 4);
        const control = self.state.floatControl();
        const left = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), 0, bytes);
        const right = if ((word & 0x8) != 0) @as(u64, 0) else vectorElement(self.state.readVector(vectorRegFromWord(word >> 16)), 0, bytes);
        self.state.writeNzcv(compareFloat(control, double, left, right));
        self.state.pc +%= 4;
        return true;
    }

    fn runAesMix(self: *Core64, word: u32) bool {
        const masked = word & 0xfffffc00;
        if (masked != 0x4e286800 and masked != 0x4e287800) {
            return false;
        }

        const input = self.state.readVector(vectorRegFromWord(word >> 5));
        const output = mixAesVector(input, masked == 0x4e287800);
        self.state.writeVector(vectorRegFromWord(word), output);
        self.state.pc +%= 4;
        return true;
    }

    fn runVectorDuplicate(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfe0fc00) != 0x0e000c00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const imm5 = @intCast(u5, (word >> 16) & 0x1f);
        if (imm5 == 0) {
            return error.UnallocatedEncoding;
        }

        const size = lowestSetBit5(imm5);
        if (size > 3) {
            return error.UnallocatedEncoding;
        }
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u6, 8) << size;
        const value = self.readSized(lane == 64, regFromWord(word >> 5), false) & ones(lane);
        const half = spreadVectorElement(value, lane);
        const result = a64_state.VectorValue{
            .low = half,
            .high = if (full) half else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    fn runVectorExtractToRegister(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbfe0fc00) != 0x0e003c00) {
            return false;
        }

        const wide = (word & 0x40000000) != 0;
        const imm5 = @intCast(u5, (word >> 16) & 0x1f);
        if (imm5 == 0) {
            return error.UnallocatedEncoding;
        }

        const size = lowestSetBit5(imm5);
        if ((size < 3 and wide) or (size == 3 and !wide) or size > 3) {
            return error.UnallocatedEncoding;
        }

        const bytes = @as(usize, 1) << size;
        const index = @as(usize, imm5) >> @intCast(u3, size + 1);
        const value = vectorElement(self.state.readVector(vectorRegFromWord(word >> 5)), index, bytes);
        self.writeSized(wide, regFromWord(word), value, false);
        self.state.pc +%= 4;
        return true;
    }

    fn runVectorAdd(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf20fc00) != 0x0e208400) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u6, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = a64_state.VectorValue{
            .low = addVectorLanes(left.low, right.low, lane),
            .high = if (full) addVectorLanes(left.high, right.high, lane) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    fn runVectorPairAdd(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf20fc00) != 0x0e20bc00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u6, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = if (full)
            a64_state.VectorValue{
                .low = pairVectorHalves(left.low, left.high, lane),
                .high = pairVectorHalves(right.low, right.high, lane),
            }
        else
            a64_state.VectorValue{
                .low = pairVectorHalves(left.low, right.low, lane),
                .high = 0,
            };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    fn runVectorEqual(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf20fc00) != 0x2e208c00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const size = @intCast(u2, (word >> 22) & 3);
        if (size == 3 and !full) {
            return error.ReservedInstruction;
        }

        const lane = @as(u6, 8) << @intCast(u3, size);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = a64_state.VectorValue{
            .low = equalVectorLanes(left.low, right.low, lane),
            .high = if (full) equalVectorLanes(left.high, right.high, lane) else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    fn runVectorAnd(self: *Core64, word: u32) bool {
        const masked = word & 0xbfe0fc00;
        if (masked != 0x0e201c00 and masked != 0x0ea01c00 and masked != 0x0ee01c00 and masked != 0x2e201c00) {
            return false;
        }

        const full = (word & 0x40000000) != 0;
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const low = switch (masked) {
            0x0e201c00 => left.low & right.low,
            0x0ea01c00 => left.low | right.low,
            0x0ee01c00 => left.low | ~right.low,
            else => left.low ^ right.low,
        };
        const high = switch (masked) {
            0x0e201c00 => left.high & right.high,
            0x0ea01c00 => left.high | right.high,
            0x0ee01c00 => left.high | ~right.high,
            else => left.high ^ right.high,
        };
        const result = a64_state.VectorValue{
            .low = low,
            .high = if (full) high else 0,
        };
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    fn runDivide(self: *Core64, word: u32) bool {
        const masked = word & 0x7fe0fc00;
        if (masked != 0x1ac00800 and masked != 0x1ac00c00) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const left = self.readSized(wide, regFromWord(word >> 5), false);
        const right = self.readSized(wide, regFromWord(word >> 16), false);
        const signed = masked == 0x1ac00c00;
        const result = if (signed)
            signedDivideSized(wide, left, right)
        else
            unsignedDivideSized(wide, left, right);
        self.writeSized(wide, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }

    fn runCrc(self: *Core64, word: u32) Core64Error!bool {
        const masked = word & 0x7fe0f000;
        if (masked != 0x1ac04000 and masked != 0x1ac05000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const size = @intCast(u2, (word >> 10) & 3);
        if (wide != (size == 3)) {
            return error.UnallocatedEncoding;
        }

        const accumulator = @intCast(u32, self.readSized(false, regFromWord(word >> 5), false));
        const value = self.readSized(wide, regFromWord(word >> 16), false);
        const result = if (masked == 0x1ac04000)
            crc32(accumulator, value, @as(u4, 1) << size)
        else
            crc32c(accumulator, value, @as(u4, 1) << size);
        self.writeSized(false, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }

    fn runVariableShift(self: *Core64, word: u32) bool {
        if ((word & 0x7fe0f000) != 0x1ac02000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const value = self.readSized(wide, regFromWord(word >> 5), false);
        const amount = @intCast(u6, self.readSized(wide, regFromWord(word >> 16), false) & if (wide) @as(u64, 63) else @as(u64, 31));
        const result = switch (@intCast(u2, (word >> 10) & 3)) {
            0 => if (wide) value << amount else @as(u64, @intCast(u32, value) << @intCast(u5, amount)),
            1 => if (wide) value >> amount else @as(u64, @intCast(u32, value) >> @intCast(u5, amount)),
            2 => if (wide) @bitCast(u64, @bitCast(i64, value) >> amount) else @as(u64, @bitCast(u32, @bitCast(i32, @intCast(u32, value)) >> @intCast(u5, amount))),
            else => rotateRightSized(wide, value, amount),
        };
        self.writeSized(wide, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }

    fn runSystemHint(self: *Core64, word: u32) bool {
        if ((word & 0xfffff01f) != 0xd503201f) {
            return false;
        }
        self.state.pc +%= 4;
        return true;
    }

    fn runLeadingZeroCount(self: *Core64, word: u32) bool {
        const masked = word & 0x7ffffc00;
        if (masked != 0x5ac01000 and masked != 0x5ac01400) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const value = self.readSized(wide, regFromWord(word >> 5), false);
        const sign = masked == 0x5ac01400;
        const result = if (sign)
            if (wide) countLeadingSignBits64(value) else @as(u64, countLeadingSignBits32(@intCast(u32, value)))
        else
            if (wide) countLeadingZeroes64(value) else @as(u64, countLeadingZeroes32(@intCast(u32, value)));
        self.writeSized(wide, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }

    fn runMultiplyAdd(self: *Core64, word: u32) bool {
        if ((word & 0x7fe00000) != 0x1b000000) {
            return false;
        }

        const wide = (word & 0x80000000) != 0;
        const left = self.readSized(wide, regFromWord(word >> 5), false);
        const right = self.readSized(wide, regFromWord(word >> 16), false);
        const addend = self.readSized(wide, regFromWord(word >> 10), false);
        const product = if (wide) left *% right else @as(u64, @intCast(u32, @intCast(u32, left) *% @intCast(u32, right)));
        const result = if ((word & 0x00008000) == 0) addend +% product else addend -% product;
        self.writeSized(wide, regFromWord(word), result, false);
        self.state.pc +%= 4;
        return true;
    }

    fn runLongMultiplyAdd(self: *Core64, word: u32) bool {
        if ((word & 0xff600000) != 0x9b200000) {
            return false;
        }

        const left = @intCast(u32, self.readSized(false, regFromWord(word >> 5), false));
        const right = @intCast(u32, self.readSized(false, regFromWord(word >> 16), false));
        const product = if ((word & 0x00800000) == 0)
            @bitCast(u64, @as(i64, @bitCast(i32, left)) *% @as(i64, @bitCast(i32, right)))
        else
            @as(u64, left) *% @as(u64, right);
        const addend = self.readSized(true, regFromWord(word >> 10), false);
        const result = if ((word & 0x00008000) == 0) addend +% product else addend -% product;
        self.writeSized(true, regFromWord(word), result, false);
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

    fn readMemory(self: *Core64, address: u64, bytes: usize) Core64Error!u64 {
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

    fn readMemoryVector(self: *Core64, address: u64) Core64Error!a64_state.VectorValue {
        const callback = self.hooks.memory.read128 orelse return error.MissingRead;
        return callback(address, self.hooks.context);
    }

    fn writeMemory(self: *Core64, address: u64, bytes: usize, value: u64) Core64Error!void {
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

    fn writeMemoryVector(self: *Core64, address: u64, value: a64_state.VectorValue) Core64Error!void {
        const callback = self.hooks.memory.write128 orelse return error.MissingWrite;
        callback(address, value, self.hooks.context);
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
    const decoded = decodeBitPattern(n, imms, immr, true) orelse return null;
    return decoded.write;
}

const BitPattern = struct {
    write: u64,
    limit: u64,
};

fn decodeBitPattern(n: bool, imms: u6, immr: u6, reject_full: bool) ?BitPattern {
    const marker = (if (n) @as(u64, 1) << 6 else @as(u64, 0)) | @as(u64, imms ^ 0x3f);
    const len = highestSetBit(marker);
    if (len < 1) {
        return null;
    }

    const levels = ones(@intCast(u6, len));
    if (reject_full and (@as(u64, imms) & levels) == levels) {
        return null;
    }

    const s = @as(u64, imms) & levels;
    const r = @as(u64, immr) & levels;
    const d = (s -% r) & levels;
    const size = @as(u6, 1) << @intCast(u3, len);
    const write = rotateRight64(replicate64(ones(@intCast(u6, s + 1)), size), @intCast(u6, r));
    const limit = replicate64(ones(@intCast(u6, d + 1)), size);
    return BitPattern{
        .write = write,
        .limit = limit,
    };
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

fn rotateRightSized(wide: bool, value: u64, amount: u6) u64 {
    if (wide) {
        return rotateRight64(value, amount);
    }
    return @as(u64, rotateRight32(@intCast(u32, value), @intCast(u5, amount & 31)));
}

fn extractRegisterBits(wide: bool, lower: u64, upper: u64, amount: u6) u64 {
    if (amount == 0) {
        return lower;
    }

    if (wide) {
        return (lower >> amount) | (upper << @intCast(u6, 64 - amount));
    }

    const shift = @intCast(u5, amount);
    return @as(u64, (@intCast(u32, lower) >> shift) | (@intCast(u32, upper) << @intCast(u5, 32 - shift)));
}

fn reverseHalfBytes(value: u64) u64 {
    return ((value & 0x00ff00ff00ff00ff) << 8) | ((value & 0xff00ff00ff00ff00) >> 8);
}

fn reverseBytes32(value: u32) u32 {
    return ((value & 0x000000ff) << 24) |
        ((value & 0x0000ff00) << 8) |
        ((value & 0x00ff0000) >> 8) |
        ((value & 0xff000000) >> 24);
}

fn reverseBytes64(value: u64) u64 {
    return (@as(u64, reverseBytes32(@intCast(u32, value))) << 32) |
        @as(u64, reverseBytes32(@intCast(u32, value >> 32)));
}

fn reverseBits32(value: u32) u32 {
    var result = ((value & 0x55555555) << 1) | ((value >> 1) & 0x55555555);
    result = ((result & 0x33333333) << 2) | ((result >> 2) & 0x33333333);
    result = ((result & 0x0f0f0f0f) << 4) | ((result >> 4) & 0x0f0f0f0f);
    return reverseBytes32(result);
}

fn reverseBits64(value: u64) u64 {
    return (@as(u64, reverseBits32(@intCast(u32, value))) << 32) |
        @as(u64, reverseBits32(@intCast(u32, value >> 32)));
}

fn lowestSetBit5(value: u5) u3 {
    var probe = value;
    var bit: u3 = 0;
    while ((probe & 1) == 0) {
        probe >>= 1;
        bit += 1;
    }
    return bit;
}

fn spreadVectorElement(value: u64, lane: u6) u64 {
    if (lane == 64) {
        return value;
    }

    const lane_value = value & ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        result |= lane_value << @intCast(u6, shift);
    }
    return result;
}

fn unsignedDivideSized(wide: bool, left: u64, right: u64) u64 {
    if (right == 0) {
        return 0;
    }

    if (wide) {
        return @divTrunc(left, right);
    }
    return @as(u64, @divTrunc(@intCast(u32, left), @intCast(u32, right)));
}

fn signedDivideSized(wide: bool, left: u64, right: u64) u64 {
    if (wide) {
        const divisor = @bitCast(i64, right);
        if (divisor == 0) {
            return 0;
        }

        const dividend = @bitCast(i64, left);
        if (dividend == @as(i64, -9223372036854775808) and divisor == -1) {
            return left;
        }
        return @bitCast(u64, @divTrunc(dividend, divisor));
    }

    const divisor = @bitCast(i32, @intCast(u32, right));
    if (divisor == 0) {
        return 0;
    }

    const dividend = @bitCast(i32, @intCast(u32, left));
    if (dividend == @as(i32, -2147483648) and divisor == -1) {
        return @as(u64, @intCast(u32, dividend));
    }
    return @as(u64, @intCast(u32, @divTrunc(dividend, divisor)));
}

fn crc32(crc: u32, value: u64, bytes: u4) u32 {
    return crc32WithPolynomial(crc, value, bytes, 0xedb88320);
}

fn crc32c(crc: u32, value: u64, bytes: u4) u32 {
    return crc32WithPolynomial(crc, value, bytes, 0x82f63b78);
}

fn crc32WithPolynomial(crc: u32, value: u64, bytes: u4, polynomial: u32) u32 {
    var result = crc;
    var remaining = value;
    var byte_index: u4 = 0;
    while (byte_index < bytes) : (byte_index += 1) {
        result ^= @intCast(u32, remaining & 0xff);
        var bit_index: u4 = 0;
        while (bit_index < 8) : (bit_index += 1) {
            const mask = if ((result & 1) != 0) polynomial else @as(u32, 0);
            result = (result >> 1) ^ mask;
        }
        remaining >>= 8;
    }
    return result;
}

fn floatInput32(control: a64_state.FloatControl, value: u32) u32 {
    if (control.fz() and isDenormal32(value)) {
        return 0;
    }
    return value;
}

fn floatInput64(control: a64_state.FloatControl, value: u64) u64 {
    if (control.fz() and isDenormal64(value)) {
        return 0;
    }
    return value;
}

fn floatOutput32(control: a64_state.FloatControl, value: u32) u32 {
    if (control.fz() and isDenormal32(value)) {
        return 0;
    }
    if (control.dn() and isNan32(value)) {
        return 0x7fc00000;
    }
    return value;
}

fn floatOutput64(control: a64_state.FloatControl, value: u64) u64 {
    if (control.fz() and isDenormal64(value)) {
        return 0;
    }
    if (control.dn() and isNan64(value)) {
        return 0x7ff8000000000000;
    }
    return value;
}

fn expandFloatConstant16(encoded: u8) u16 {
    const sign = @as(u16, encoded >> 7);
    const exponent_base = if (((encoded >> 6) & 1) != 0) @as(u16, 0x0c) else @as(u16, 0x10);
    const exponent = exponent_base | @as(u16, (encoded >> 4) & 3);
    const fraction = @as(u16, encoded & 0xf) << 6;
    return (sign << 15) | (exponent << 10) | fraction;
}

fn expandFloatConstant32(encoded: u8) u32 {
    const sign = @as(u32, encoded >> 7);
    const exponent_base = if (((encoded >> 6) & 1) != 0) @as(u32, 0x7c) else @as(u32, 0x80);
    const exponent = exponent_base | @as(u32, (encoded >> 4) & 3);
    const fraction = @as(u32, encoded & 0xf) << 19;
    return (sign << 31) | (exponent << 23) | fraction;
}

fn expandFloatConstant64(encoded: u8) u64 {
    const sign = @as(u64, encoded >> 7);
    const exponent_base = if (((encoded >> 6) & 1) != 0) @as(u64, 0x3fc) else @as(u64, 0x400);
    const exponent = exponent_base | @as(u64, (encoded >> 4) & 3);
    const fraction = @as(u64, encoded & 0xf) << 48;
    return (sign << 63) | (exponent << 52) | fraction;
}

fn float32To64(control: a64_state.FloatControl, value: u32) u64 {
    const input = @bitCast(f32, floatInput32(control, value));
    return floatOutput64(control, @bitCast(u64, @floatCast(f64, input)));
}

fn float64To32(control: a64_state.FloatControl, value: u64) u32 {
    const input = @bitCast(f64, floatInput64(control, value));
    return floatOutput32(control, @bitCast(u32, @floatCast(f32, input)));
}

fn floatAdd(control: a64_state.FloatControl, double: bool, left: u64, right: u64) u64 {
    if (double) {
        return floatOutput64(control, @bitCast(u64, @bitCast(f64, floatInput64(control, left)) + @bitCast(f64, floatInput64(control, right))));
    }
    const result = @bitCast(u32, @bitCast(f32, floatInput32(control, @intCast(u32, left))) + @bitCast(f32, floatInput32(control, @intCast(u32, right))));
    return @as(u64, floatOutput32(control, result));
}

fn floatDiv(control: a64_state.FloatControl, double: bool, left: u64, right: u64) u64 {
    if (double) {
        return floatOutput64(control, @bitCast(u64, @bitCast(f64, floatInput64(control, left)) / @bitCast(f64, floatInput64(control, right))));
    }
    const result = @bitCast(u32, @bitCast(f32, floatInput32(control, @intCast(u32, left))) / @bitCast(f32, floatInput32(control, @intCast(u32, right))));
    return @as(u64, floatOutput32(control, result));
}

fn floatMul(control: a64_state.FloatControl, double: bool, left: u64, right: u64) u64 {
    if (double) {
        return floatOutput64(control, @bitCast(u64, @bitCast(f64, floatInput64(control, left)) * @bitCast(f64, floatInput64(control, right))));
    }
    const result = @bitCast(u32, @bitCast(f32, floatInput32(control, @intCast(u32, left))) * @bitCast(f32, floatInput32(control, @intCast(u32, right))));
    return @as(u64, floatOutput32(control, result));
}

fn floatSub(control: a64_state.FloatControl, double: bool, left: u64, right: u64) u64 {
    if (double) {
        return floatOutput64(control, @bitCast(u64, @bitCast(f64, floatInput64(control, left)) - @bitCast(f64, floatInput64(control, right))));
    }
    const result = @bitCast(u32, @bitCast(f32, floatInput32(control, @intCast(u32, left))) - @bitCast(f32, floatInput32(control, @intCast(u32, right))));
    return @as(u64, floatOutput32(control, result));
}

fn negateFloat(double: bool, value: u64) u64 {
    if (double) {
        return value ^ 0x8000000000000000;
    }
    return @as(u64, @intCast(u32, value) ^ 0x80000000);
}

fn compareFloat(control: a64_state.FloatControl, double: bool, left: u64, right: u64) u32 {
    if (double) {
        const left_word = floatInput64(control, left);
        const right_word = floatInput64(control, right);
        if (isNan64(left_word) or isNan64(right_word)) {
            return 0x30000000;
        }
        const left_value = @bitCast(f64, left_word);
        const right_value = @bitCast(f64, right_word);
        if (left_value == right_value) {
            return 0x60000000;
        }
        if (left_value < right_value) {
            return 0x80000000;
        }
        return 0x20000000;
    }

    const left_word = floatInput32(control, @intCast(u32, left));
    const right_word = floatInput32(control, @intCast(u32, right));
    if (isNan32(left_word) or isNan32(right_word)) {
        return 0x30000000;
    }
    const left_value = @bitCast(f32, left_word);
    const right_value = @bitCast(f32, right_word);
    if (left_value == right_value) {
        return 0x60000000;
    }
    if (left_value < right_value) {
        return 0x80000000;
    }
    return 0x20000000;
}

fn isDenormal32(value: u32) bool {
    const magnitude = value & 0x7fffffff;
    return magnitude != 0 and magnitude <= 0x007fffff;
}

fn isDenormal64(value: u64) bool {
    const magnitude = value & 0x7fffffffffffffff;
    return magnitude != 0 and magnitude <= 0x000fffffffffffff;
}

fn isNan32(value: u32) bool {
    return (value & 0x7fffffff) > 0x7f800000;
}

fn isNan64(value: u64) bool {
    return (value & 0x7fffffffffffffff) > 0x7ff0000000000000;
}

fn aesDouble(value: u8) u8 {
    const shifted = (@as(u16, value) << 1) & 0xff;
    const reduced = if ((value & 0x80) != 0) shifted ^ 0x1b else shifted;
    return @intCast(u8, reduced);
}

fn aesProduct(value: u8, factor: u8) u8 {
    var left = value;
    var right = factor;
    var result: u8 = 0;
    while (right != 0) : (right >>= 1) {
        if ((right & 1) != 0) {
            result ^= left;
        }
        left = aesDouble(left);
    }
    return result;
}

fn vectorByte(value: a64_state.VectorValue, index: usize) u8 {
    const shift = @intCast(u6, (index & 7) * 8);
    const word = if (index < 8) value.low else value.high;
    return @intCast(u8, (word >> shift) & 0xff);
}

fn vectorElement(value: a64_state.VectorValue, index: usize, bytes: usize) u64 {
    var result: u64 = 0;
    var byte_index: usize = 0;
    while (byte_index < bytes) : (byte_index += 1) {
        result |= @as(u64, vectorByte(value, index * bytes + byte_index)) << @intCast(u6, byte_index * 8);
    }
    return result;
}

fn setVectorByte(value: *a64_state.VectorValue, index: usize, byte: u8) void {
    const shift = @intCast(u6, (index & 7) * 8);
    const mask = @as(u64, 0xff) << shift;
    const shifted = @as(u64, byte) << shift;
    if (index < 8) {
        value.low = (value.low & ~mask) | shifted;
    } else {
        value.high = (value.high & ~mask) | shifted;
    }
}

fn setVectorElement(value: *a64_state.VectorValue, index: usize, bytes: usize, element: u64) void {
    var byte_index: usize = 0;
    while (byte_index < bytes) : (byte_index += 1) {
        const byte = @intCast(u8, (element >> @intCast(u6, byte_index * 8)) & 0xff);
        setVectorByte(value, index * bytes + byte_index, byte);
    }
}

fn mixAesVector(input: a64_state.VectorValue, inverse: bool) a64_state.VectorValue {
    var output = a64_state.VectorValue{ .low = 0, .high = 0 };
    var column: usize = 0;
    while (column < 16) : (column += 4) {
        const a = vectorByte(input, column);
        const b = vectorByte(input, column + 1);
        const c = vectorByte(input, column + 2);
        const d = vectorByte(input, column + 3);
        if (inverse) {
            setVectorByte(&output, column, aesProduct(a, 0x0e) ^ aesProduct(b, 0x0b) ^ aesProduct(c, 0x0d) ^ aesProduct(d, 0x09));
            setVectorByte(&output, column + 1, aesProduct(a, 0x09) ^ aesProduct(b, 0x0e) ^ aesProduct(c, 0x0b) ^ aesProduct(d, 0x0d));
            setVectorByte(&output, column + 2, aesProduct(a, 0x0d) ^ aesProduct(b, 0x09) ^ aesProduct(c, 0x0e) ^ aesProduct(d, 0x0b));
            setVectorByte(&output, column + 3, aesProduct(a, 0x0b) ^ aesProduct(b, 0x0d) ^ aesProduct(c, 0x09) ^ aesProduct(d, 0x0e));
        } else {
            const fold = a ^ b ^ c ^ d;
            setVectorByte(&output, column, a ^ aesDouble(a ^ b) ^ fold);
            setVectorByte(&output, column + 1, b ^ aesDouble(b ^ c) ^ fold);
            setVectorByte(&output, column + 2, c ^ aesDouble(c ^ d) ^ fold);
            setVectorByte(&output, column + 3, d ^ aesDouble(d ^ a) ^ fold);
        }
    }
    return output;
}

fn addVectorLanes(left: u64, right: u64, lane: u6) u64 {
    if (lane == 64) {
        return left +% right;
    }

    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        const sum = ((left >> amount) & mask) +% ((right >> amount) & mask);
        result |= (sum & mask) << amount;
    }
    return result;
}

fn equalVectorLanes(left: u64, right: u64, lane: u6) u64 {
    if (lane == 64) {
        return if (left == right) ~@as(u64, 0) else 0;
    }

    const mask = ones(lane);
    var result: u64 = 0;
    var shift: u8 = 0;
    while (shift < 64) : (shift += lane) {
        const amount = @intCast(u6, shift);
        if (((left >> amount) & mask) == ((right >> amount) & mask)) {
            result |= mask << amount;
        }
    }
    return result;
}

fn pairVectorHalves(first: u64, second: u64, lane: u6) u64 {
    if (lane == 64) {
        return first +% second;
    }

    return pairVectorHalf(first, lane) | (pairVectorHalf(second, lane) << @intCast(u6, 32));
}

fn pairVectorHalf(value: u64, lane: u6) u64 {
    const mask = ones(lane);
    const lane_step = @intCast(u8, lane);
    var result: u64 = 0;
    var input_shift: u8 = 0;
    var output_shift: u8 = 0;
    while (input_shift < 64) {
        const first_shift = @intCast(u6, input_shift);
        const second_shift = @intCast(u6, input_shift + lane_step);
        const output_amount = @intCast(u6, output_shift);
        const sum = ((value >> first_shift) & mask) +% ((value >> second_shift) & mask);
        result |= (sum & mask) << output_amount;
        input_shift += lane_step * 2;
        output_shift += lane_step;
    }
    return result;
}

fn countLeadingZeroes32(value: u32) u32 {
    if (value == 0) {
        return 32;
    }

    var count: u32 = 0;
    var mask: u32 = 0x80000000;
    while ((value & mask) == 0) : (mask >>= 1) {
        count += 1;
    }
    return count;
}

fn countLeadingZeroes64(value: u64) u64 {
    if (value == 0) {
        return 64;
    }

    var count: u64 = 0;
    var mask: u64 = 0x8000000000000000;
    while ((value & mask) == 0) : (mask >>= 1) {
        count += 1;
    }
    return count;
}

fn countLeadingSignBits32(value: u32) u32 {
    const folded = if ((value & 0x80000000) != 0) ~value else value;
    return countLeadingZeroes32(folded) - 1;
}

fn countLeadingSignBits64(value: u64) u64 {
    const folded = if ((value & 0x8000000000000000) != 0) ~value else value;
    return countLeadingZeroes64(folded) - 1;
}

fn regFromWord(value: u32) a64_state.GeneralReg {
    return @intToEnum(a64_state.GeneralReg, @intCast(u5, value & 0x1f));
}

fn vectorRegFromWord(value: u32) a64_state.VectorReg {
    return @intToEnum(a64_state.VectorReg, @intCast(u5, value & 0x1f));
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
