const arm_state = @import("arm_state.zig");

pub const TraceError = error{
    Full,
};

pub const ValueKind = enum(u8) {
    none,
    bit,
    byte,
    word,
    reg,
};

pub const EventKind = enum(u8) {
    literal_bit,
    literal_byte,
    literal_word,
    literal_reg,
    load_reg,
    store_reg,
    load_carry,
    store_negative,
    store_zero,
    store_carry,
    low_byte,
    high_bit,
    equal_zero,
    shift_left,
    shift_right,
    carry_result,
};

pub const Value = union(ValueKind) {
    none: void,
    bit: bool,
    byte: u8,
    word: u32,
    reg: arm_state.ArmReg,
};

pub const Event = struct {
    kind: EventKind,
    value: Value,
    arg0: usize,
    arg1: usize,
    arg2: usize,
};

pub const Tape = struct {
    events: [128]Event,
    len: usize,

    pub fn init() Tape {
        return Tape{
            .events = [_]Event{emptyEvent()} ** 128,
            .len = 0,
        };
    }

    pub fn push(self: *Tape, kind: EventKind, value: Value, arg0: usize, arg1: usize, arg2: usize) TraceError!usize {
        if (self.len >= self.events.len) {
            return error.Full;
        }
        const index = self.len;
        self.events[index] = Event{
            .kind = kind,
            .value = value,
            .arg0 = arg0,
            .arg1 = arg1,
            .arg2 = arg2,
        };
        self.len += 1;
        return index;
    }

    pub fn literalByte(self: *Tape, value: u8) TraceError!usize {
        return self.push(.literal_byte, Value{ .byte = value }, 0, 0, 0);
    }

    pub fn literalReg(self: *Tape, value: arm_state.ArmReg) TraceError!usize {
        return self.push(.literal_reg, Value{ .reg = value }, 0, 0, 0);
    }

    pub fn loadReg(self: *Tape, reg: usize) TraceError!usize {
        return self.push(.load_reg, Value{ .none = {} }, reg, 0, 0);
    }

    pub fn storeReg(self: *Tape, reg: usize, value: usize) TraceError!usize {
        return self.push(.store_reg, Value{ .none = {} }, reg, value, 0);
    }

    pub fn loadCarry(self: *Tape) TraceError!usize {
        return self.push(.load_carry, Value{ .none = {} }, 0, 0, 0);
    }

    pub fn storeNegative(self: *Tape, value: usize) TraceError!usize {
        return self.push(.store_negative, Value{ .none = {} }, value, 0, 0);
    }

    pub fn storeZero(self: *Tape, value: usize) TraceError!usize {
        return self.push(.store_zero, Value{ .none = {} }, value, 0, 0);
    }

    pub fn storeCarry(self: *Tape, value: usize) TraceError!usize {
        return self.push(.store_carry, Value{ .none = {} }, value, 0, 0);
    }

    pub fn lowByte(self: *Tape, value: usize) TraceError!usize {
        return self.push(.low_byte, Value{ .none = {} }, value, 0, 0);
    }

    pub fn highBit(self: *Tape, value: usize) TraceError!usize {
        return self.push(.high_bit, Value{ .none = {} }, value, 0, 0);
    }

    pub fn equalZero(self: *Tape, value: usize) TraceError!usize {
        return self.push(.equal_zero, Value{ .none = {} }, value, 0, 0);
    }

    pub fn shiftLeft(self: *Tape, value: usize, amount: usize, carry: usize) TraceError!usize {
        return self.push(.shift_left, Value{ .none = {} }, value, amount, carry);
    }

    pub fn shiftRight(self: *Tape, value: usize, amount: usize, carry: usize) TraceError!usize {
        return self.push(.shift_right, Value{ .none = {} }, value, amount, carry);
    }

    pub fn carryResult(self: *Tape, value: usize) TraceError!usize {
        return self.push(.carry_result, Value{ .none = {} }, value, 0, 0);
    }
};

fn emptyEvent() Event {
    return Event{
        .kind = .literal_bit,
        .value = Value{ .none = {} },
        .arg0 = 0,
        .arg1 = 0,
        .arg2 = 0,
    };
}

