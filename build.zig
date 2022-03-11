const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("jit-core", "jit_core.zig");
    lib.setBuildMode(mode);
    lib.install();
}
