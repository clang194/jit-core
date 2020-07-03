const arm_state = @import("arm_state.zig");
const thumb_exec = @import("thumb_exec.zig");

pub const CoreError = error{
    Busy,
    UnknownInstruction,
    Full,
};

pub const Core = struct {
    state: arm_state.MachineState,
    hooks: arm_state.HostHooks,
    active: bool,
    halt: bool,

    pub fn init(hooks: arm_state.HostHooks) Core {
        return Core{
            .state = arm_state.MachineState.zeroed(),
            .hooks = hooks,
            .active = false,
            .halt = false,
        };
    }

    pub fn runThumbWord(self: *Core, word: u16, budget: usize) CoreError!usize {
        if (self.active) {
            return error.Busy;
        }
        self.active = true;
        defer self.active = false;

        self.halt = false;
        var used: usize = 0;
        while (used < budget and !self.halt) : (used += 1) {
            try thumb_exec.runThumb(word, &self.state);
        }
        return used;
    }

    pub fn clearTranslatedState(self: *Core) void {
        _ = self;
    }

    pub fn requestHalt(self: *Core) void {
        self.halt = true;
    }

    pub fn isActive(self: *const Core) bool {
        return self.active;
    }

    pub fn regs(self: *Core) *[16]u32 {
        return &self.state.regs;
    }

    pub fn regsCopy(self: *const Core) [16]u32 {
        return self.state.regs;
    }

    pub fn status(self: *Core) *u32 {
        return &self.state.cpsr;
    }

    pub fn statusCopy(self: *const Core) u32 {
        return self.state.cpsr;
    }
};

