const std = @import("std");

pub fn build(b: *std.Build) void {
    const t = b.standardTargetOptions(.{});
    const o = b.standardOptimizeOption(.{});

    const eno = b.dependency("enogine", .{}).module("eno");

    {
        const exe = b.addExecutable(.{
            .name = "digger_replace",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = t,
                .optimize = o,
            }),
        });
        exe.root_module.addImport("eno", eno);
        b.installArtifact(exe);

        const run_step = b.step("run", "Run the application");
        const run_exe = b.addRunArtifact(exe);
        run_step.dependOn(&run_exe.step);
    }

    {
        const test_exe = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = t,
                .optimize = o,
            }),
            .test_runner = .{
                .mode = .simple,
                .path = b.path("test_runner.zig"),
            },
        });
        const run_test_step = b.step("test", "Run unit tests");
        const run_test = b.addRunArtifact(test_exe);

        test_exe.root_module.addImport("eno", eno);
        run_test_step.dependOn(&run_test.step);
    }
}
