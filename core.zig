const arm_state = @import("arm_state.zig");
const arm_exec = @import("arm_exec.zig");
const thumb_exec = @import("thumb_exec.zig");

pub const CoreError = error{
    Busy,
    UnknownInstruction,
    Unpredictable,
    Full,
    MissingRead,
    MissingWrite,
};

pub const CoreImage = struct {
    state: arm_state.MachineState,
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

    fn addCycles(self: *Core, count: usize) void {
        if (self.hooks.cycles.add) |callback| {
            callback(count, self.hooks.context);
        }
    }

    fn hasCycles(self: *Core, budget: usize, used: usize) bool {
        if (self.hooks.cycles.remaining) |callback| {
            return callback(self.hooks.context) != 0;
        }
        return used < budget;
    }

    pub fn runThumbWord(self: *Core, word: u16, budget: usize) CoreError!usize {
        if (self.active) {
            return error.Busy;
        }
        self.active = true;
        defer self.active = false;

        self.halt = false;
        var used: usize = 0;
        while (self.hasCycles(budget, used) and !self.halt) {
            try thumb_exec.runThumbWithHooks(word, &self.state, self.hooks);
            used += 1;
            self.addCycles(1);
        }
        return used;
    }

    pub fn run(self: *Core, budget: usize) CoreError!usize {
        if (self.active) {
            return error.Busy;
        }
        self.active = true;
        defer self.active = false;

        self.halt = false;
        var used: usize = 0;
        while (self.hasCycles(budget, used) and !self.halt) {
            if (!self.state.thumb()) {
                const pc = self.state.read(.pc);
                arm_exec.runArmWithHooks(&self.state, self.hooks) catch |err| switch (err) {
                    error.Unpredictable => {
                        try self.raiseFault(pc, .unpredictable_instruction, error.Unpredictable);
                        used += 1;
                        self.addCycles(1);
                        continue;
                    },
                    error.UnknownInstruction => return error.UnknownInstruction,
                    error.MissingRead => return error.MissingRead,
                    error.MissingWrite => return error.MissingWrite,
                };
                used += 1;
                self.addCycles(1);
                continue;
            }

            const pc = self.state.read(.pc);
            const fetched = thumb_exec.readThumbWord(self.hooks, pc) catch |err| switch (err) {
                error.UnknownInstruction => {
                    try self.interpretOne(pc);
                    used += 1;
                    self.addCycles(1);
                    continue;
                },
                else => return err,
            };

            if (fetched.size == 2 and thumb_exec.isStop(@intCast(u16, fetched.word & 0xffff))) {
                try self.raiseFault(pc, .undefined_instruction, error.UnknownInstruction);
                used += 1;
                self.addCycles(1);
                continue;
            }

            if (fetched.size == 2) {
                if (thumb_exec.branchTarget(@intCast(u16, fetched.word & 0xffff), pc)) |target| {
                    self.state.write(.pc, target);
                    used += 1;
                    self.addCycles(1);
                    continue;
                }
            }

            thumb_exec.runThumbPacketWithHooks(fetched, &self.state, self.hooks) catch |err| switch (err) {
                error.UndefinedInstruction => {
                    try self.raiseFault(pc, .undefined_instruction, error.UnknownInstruction);
                    used += 1;
                    self.addCycles(1);
                    continue;
                },
                error.Unpredictable => {
                    try self.raiseFault(pc, .unpredictable_instruction, error.Unpredictable);
                    used += 1;
                    self.addCycles(1);
                    continue;
                },
                error.UnknownInstruction => {
                    try self.interpretOne(pc);
                    used += 1;
                    self.addCycles(1);
                    continue;
                },
                else => return err,
            };
            if (self.state.read(.pc) == pc) {
                self.state.write(.pc, pc + fetched.size);
            }
            used += 1;
            self.addCycles(1);
        }
        return used;
    }

    fn raiseFault(self: *Core, pc: u32, kind: arm_state.FaultKind, fallback: CoreError) CoreError!void {
        if (self.hooks.exception) |callback| {
            callback(pc, kind, &self.state, self.hooks.context);
            return;
        }
        return fallback;
    }

    fn interpretOne(self: *Core, pc: u32) CoreError!void {
        if (self.hooks.fallback) |callback| {
            callback(pc, &self.state, self.hooks.context);
            return;
        }
        return error.UnknownInstruction;
    }

    pub fn clearTranslatedState(self: *Core) void {
        if (self.active) {
            self.halt = true;
        }
    }

    pub fn resetState(self: *Core) CoreError!void {
        if (self.active) {
            return error.Busy;
        }
        self.state = arm_state.MachineState.zeroed();
        self.halt = false;
    }

    pub fn saveImage(self: *const Core) CoreImage {
        var image = CoreImage{ .state = self.state };
        image.state.exclusive = false;
        image.state.exclusive_address = 0;
        return image;
    }

    pub fn saveInto(self: *const Core, image: *CoreImage) void {
        image.state = self.state;
        image.state.exclusive = false;
        image.state.exclusive_address = 0;
    }

    pub fn loadImage(self: *Core, image: *const CoreImage) void {
        self.state = image.state;
        self.state.exclusive = false;
        self.state.exclusive_address = 0;
        self.halt = false;
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

    pub fn regsView(self: *const Core) *const [16]u32 {
        return &self.state.regs;
    }

    pub fn floatRegs(self: *Core) *[64]u32 {
        return &self.state.float_regs;
    }

    pub fn floatRegsView(self: *const Core) *const [64]u32 {
        return &self.state.float_regs;
    }

    pub fn status(self: *Core) *u32 {
        return &self.state.cpsr;
    }

    pub fn statusCopy(self: *const Core) u32 {
        return self.state.cpsr;
    }

    pub fn floatStatus(self: *Core) *u32 {
        return &self.state.fpscr;
    }

    pub fn floatStatusCopy(self: *const Core) u32 {
        return self.state.readFloatStatus();
    }

    pub fn writeFloatStatus(self: *Core, value: u32) void {
        self.state.writeFloatStatus(value);
    }
};
