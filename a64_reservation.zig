pub const ReservationTable64 = struct {
    locked: u8,
    slots: []u64,

    const invalid = @as(u64, 0xdeaddeaddeaddead);
    const granule_mask = @as(u64, 0xfffffffffffffff0);

    pub fn init(slots: []u64) ReservationTable64 {
        var table = ReservationTable64{
            .locked = 0,
            .slots = slots,
        };
        table.clear();
        return table;
    }

    pub fn count(self: *const ReservationTable64) usize {
        return self.slots.len;
    }

    pub fn mark(self: *ReservationTable64, slot: usize, address: u64, bytes: usize) void {
        _ = bytes;
        if (slot >= self.slots.len) {
            return;
        }
        const base = address & granule_mask;
        self.lock();
        self.slots[slot] = base;
        self.unlock();
    }

    pub fn claim(self: *ReservationTable64, slot: usize, address: u64, bytes: usize) bool {
        _ = bytes;
        if (slot >= self.slots.len) {
            return false;
        }
        const base = address & granule_mask;
        self.lock();
        if (self.slots[slot] != base) {
            self.unlock();
            return false;
        }
        var index: usize = 0;
        while (index < self.slots.len) : (index += 1) {
            if (self.slots[index] == base) {
                self.slots[index] = invalid;
            }
        }
        self.unlock();
        return true;
    }

    pub fn clear(self: *ReservationTable64) void {
        self.lock();
        var index: usize = 0;
        while (index < self.slots.len) : (index += 1) {
            self.slots[index] = invalid;
        }
        self.unlock();
    }

    fn lock(self: *ReservationTable64) void {
        while (@atomicRmw(u8, &self.locked, .Xchg, 1, .Acquire) != 0) {}
    }

    fn unlock(self: *ReservationTable64) void {
        @atomicStore(u8, &self.locked, 0, .Release);
    }
};
