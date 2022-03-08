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
    pub fn runLoadStore(self: *Core64, word: u32) Core64Error!bool {
        const exclusive = self.runExclusiveLoadStore(word) catch |err| {
            return err;
        };
        if (exclusive) {
            return true;
        }

        if ((word & 0x3ffffc00) == 0x089f7c00 or (word & 0x3ffffc00) == 0x089ffc00 or (word & 0x3ffffc00) == 0x08df7c00 or (word & 0x3ffffc00) == 0x08dffc00) {
            return try self.runOrderedLoadStore(word);
        }

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

        if ((word & 0x3f200c00) == 0x3c200800) {
            return try self.runVectorLoadStoreRegisterOffset(word);
        }

        if ((word & 0x3f200c00) == 0x38200800) {
            return try self.runLoadStoreRegisterOffset(word);
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

    pub fn runExclusiveLoadStore(self: *Core64, word: u32) Core64Error!bool {
        const masked_store = word & 0x3fe0fc00;
        const single_store = masked_store == 0x08007c00 or masked_store == 0x0800fc00;
        const masked_load = word & 0x3ffffc00;
        const single_load = masked_load == 0x085f7c00 or masked_load == 0x085ffc00;
        const masked_pair_store = word & 0xbfe08000;
        const pair_store = masked_pair_store == 0x88200000 or masked_pair_store == 0x88208000;
        const masked_pair_load = word & 0xbfff8000;
        const pair_load = masked_pair_load == 0x887f0000 or masked_pair_load == 0x887f8000;
        const store = single_store or pair_store;
        const load = single_load or pair_load;
        const pair = pair_store or pair_load;
        if (!store and !load) {
            return false;
        }

        const size = if (pair) @intCast(u2, 2 | ((word >> 30) & 1)) else @intCast(u2, word >> 30);
        const base_reg = regFromWord(word >> 5);
        const data_reg = regFromWord(word);
        const address = self.readSized(true, base_reg, true);

        if (store) {
            const status_reg = regFromWord(word >> 16);
            const second_reg = regFromWord(word >> 10);
            if (pair and (status_reg == data_reg or status_reg == second_reg)) {
                return error.Unpredictable;
            }
            if (status_reg == base_reg and base_reg != .sp) {
                return error.Unpredictable;
            }
            if (self.exclusiveHolds(address)) {
                self.state.exclusive = false;
                if (pair) {
                    if (size == 3) {
                        try self.writeMemoryVector(address, a64_state.VectorValue{
                            .low = self.readSized(true, data_reg, false),
                            .high = self.readSized(true, second_reg, false),
                        });
                    } else {
                        const low = @intCast(u32, self.readSized(false, data_reg, false));
                        const high = @intCast(u32, self.readSized(false, second_reg, false));
                        try self.writeMemory(address, 8, @as(u64, low) | (@as(u64, high) << 32));
                    }
                } else {
                    try self.writeMemory(address, @as(usize, 1) << size, self.readSized(size == 3, data_reg, false));
                }
                self.writeSized(false, status_reg, 0, false);
            } else {
                self.writeSized(false, status_reg, 1, false);
            }
        } else {
            const second_reg = regFromWord(word >> 10);
            if (pair and data_reg == second_reg) {
                return error.Unpredictable;
            }
            self.state.exclusive = true;
            self.state.exclusive_address = address;
            if (pair) {
                if (size == 3) {
                    const value = try self.readMemoryVector(address);
                    self.writeSized(true, data_reg, value.low, false);
                    self.writeSized(true, second_reg, value.high, false);
                } else {
                    const value = try self.readMemory(address, 8);
                    self.writeSized(false, data_reg, value, false);
                    self.writeSized(false, second_reg, value >> 32, false);
                }
            } else {
                const value = try self.readMemory(address, @as(usize, 1) << size);
                self.writeSized(size == 3, data_reg, value, false);
            }
        }

        self.state.pc +%= 4;
        return true;
    }

    pub fn runOrderedLoadStore(self: *Core64, word: u32) Core64Error!bool {
        const size = @intCast(u2, word >> 30);
        const base_reg = regFromWord(word >> 5);
        const data_reg = regFromWord(word);
        const bytes = @as(usize, 1) << size;
        const address = self.readSized(true, base_reg, true);

        const masked = word & 0x3ffffc00;
        if (masked == 0x089f7c00 or masked == 0x089ffc00) {
            try self.writeMemory(address, bytes, self.readSized(size == 3, data_reg, false));
        } else {
            const value = try self.readMemory(address, bytes);
            self.writeSized(size == 3, data_reg, value, false);
        }

        self.state.pc +%= 4;
        return true;
    }

    pub fn runLoadStoreRegister(self: *Core64, word: u32, offset: u64, writeback: bool, postindex: bool) Core64Error!bool {
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

    pub fn runLoadStoreRegisterOffset(self: *Core64, word: u32) Core64Error!bool {
        const option = @intCast(u3, (word >> 13) & 7);
        if ((option & 2) == 0) {
            return error.UnallocatedEncoding;
        }

        const size = @intCast(u2, word >> 30);
        const opcode = @intCast(u2, (word >> 22) & 3);
        const base_reg = regFromWord(word >> 5);
        const data_reg = regFromWord(word);
        const bytes = @as(usize, 1) << size;

        if ((opcode & 2) != 0 and size == 3) {
            if ((opcode & 1) != 0) {
                return error.UnallocatedEncoding;
            }
            self.state.pc +%= 4;
            return true;
        }
        if ((opcode & 2) != 0 and size == 2 and (opcode & 1) != 0) {
            return error.UnallocatedEncoding;
        }

        const shift = if (((word >> 12) & 1) != 0) @intCast(u3, size) else @as(u3, 0);
        const offset = self.extendedReg(true, regFromWord(word >> 16), option, shift);
        const address = self.readSized(true, base_reg, true) +% offset;

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

        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorLoadStoreRegisterOffset(self: *Core64, word: u32) Core64Error!bool {
        const option = @intCast(u3, (word >> 13) & 7);
        if ((option & 2) == 0) {
            return error.UnallocatedEncoding;
        }

        const scale = @intCast(u3, ((word >> 30) & 3) | (((word >> 23) & 1) << 2));
        if (scale > 4) {
            return error.UnallocatedEncoding;
        }

        const base_reg = regFromWord(word >> 5);
        const data_reg = vectorRegFromWord(word);
        const bytes = @as(usize, 1) << scale;
        const shift = if (((word >> 12) & 1) != 0) scale else @as(u3, 0);
        const offset = self.extendedReg(true, regFromWord(word >> 16), option, shift);
        const address = self.readSized(true, base_reg, true) +% offset;

        if (((word >> 22) & 1) != 0) {
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

        self.state.pc +%= 4;
        return true;
    }

    pub fn runLoadStoreUnprivileged(self: *Core64, word: u32) Core64Error!bool {
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

    pub fn runVectorLoadStoreRegister(self: *Core64, word: u32, offset: u64, writeback: bool, postindex: bool) Core64Error!bool {
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

};
