const float_status = @import("float_status.zig");
const main = @import("a64_core.zig");
const Core64 = main.Core64;
const Core64Error = main.Core64Error;
usingnamespace @import("a64_float_control.zig");
usingnamespace @import("a64_immediate_vectors.zig");
usingnamespace @import("a64_vector_complex.zig");

fn complexFloatShape(word: u32) Core64Error!struct { full: bool, double: bool } {
    const size = @intCast(u2, (word >> 22) & 3);
    const full = (word & 0x40000000) != 0;
    if (size == 1) {
        return error.MissingFallback;
    }
    if (size == 0 or (size == 3 and !full)) {
        return error.UnallocatedEncoding;
    }
    return .{ .full = full, .double = size == 3 };
}

pub const Core64Methods = struct {
    pub fn runVectorComplexAdd(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf20ec00) != 0x2e00e400) {
            return false;
        }

        const shape = try complexFloatShape(word);
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const result = addComplexFloatVector(self.state.floatControl(), self.hooks.float_nan_mode, shape.double, shape.full, left, right, ((word >> 12) & 1) != 0);
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }

    pub fn runVectorComplexMultiplyAdd(self: *Core64, word: u32) Core64Error!bool {
        if ((word & 0xbf20e400) != 0x2e00c400) {
            return false;
        }

        const shape = try complexFloatShape(word);
        const addend = self.state.readVector(vectorRegFromWord(word));
        const left = self.state.readVector(vectorRegFromWord(word >> 5));
        const right = self.state.readVector(vectorRegFromWord(word >> 16));
        const control = effectiveFloatControl(self.state.floatControl(), self.hooks.float_nan_mode);
        var status = float_status.FloatStatus.init(self.state.floatStatus());
        const result = multiplyAddComplexFloatVector(control, &status, shape.double, shape.full, addend, left, right, @intCast(u2, (word >> 11) & 3)) catch return error.MissingFallback;
        self.state.writeFloatStatus(status.raw());
        self.state.writeVector(vectorRegFromWord(word), result);
        self.state.pc +%= 4;
        return true;
    }
};
