const a64_state = @import("a64_state.zig");
const float_status = @import("float_status.zig");

pub const FloatException = enum {
    invalid_operation,
    divide_by_zero,
    overflow,
    underflow,
    inexact,
    input_denormal,
};

pub const FloatExceptionError = error{
    EnabledTrap,
};

pub fn processFloatException(kind: FloatException, control: a64_state.FloatControl, status: *float_status.FloatStatus) FloatExceptionError!void {
    switch (kind) {
        .invalid_operation => {
            if (control.ioe()) {
                return error.EnabledTrap;
            }
            status.setInvalidOperation(true);
        },
        .divide_by_zero => {
            if (control.dze()) {
                return error.EnabledTrap;
            }
            status.setDivideByZero(true);
        },
        .overflow => {
            if (control.ofe()) {
                return error.EnabledTrap;
            }
            status.setOverflow(true);
        },
        .underflow => {
            if (control.ufe()) {
                return error.EnabledTrap;
            }
            status.setUnderflow(true);
        },
        .inexact => {
            if (control.ixe()) {
                return error.EnabledTrap;
            }
            status.setInexact(true);
        },
        .input_denormal => {
            if (control.ide()) {
                return error.EnabledTrap;
            }
            status.setInputDenormal(true);
        },
    }
}
