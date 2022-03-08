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
    pub fn runVectorStructureTransfer(self: *Core64, word: u32) Core64Error!bool {
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

    pub fn readVectorPairMemory(self: *Core64, address: u64, bytes: usize) Core64Error!a64_state.VectorValue {
        if (bytes == 16) {
            return try self.readMemoryVector(address);
        }
        return a64_state.VectorValue{
            .low = try self.readMemory(address, bytes),
            .high = 0,
        };
    }

    pub fn writeVectorPairMemory(self: *Core64, address: u64, bytes: usize, value: a64_state.VectorValue) Core64Error!void {
        if (bytes == 16) {
            try self.writeMemoryVector(address, value);
            return;
        }
        try self.writeMemory(address, bytes, value.low);
    }


};
