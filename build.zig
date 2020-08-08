const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("jit-core", "jit_core.zig");
    lib.setBuildMode(mode);
    lib.install();


}
