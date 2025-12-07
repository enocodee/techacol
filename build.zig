const std = @import("std");

pub fn build(b: *std.Build) void {
    const t = b.standardTargetOptions(.{});
    const o = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = t,
        .optimize = o,
    });

    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const ecs_mod = b.addModule("ecs", .{
        .root_source_file = b.path("src/ecs.zig"),
        .target = t,
        .optimize = o,
        .imports = &.{
            .{ .name = "raylib", .module = raylib },
        },
    });

    {
        const exe = b.addExecutable(.{
            .name = "digger_replace",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = t,
                .optimize = o,
            }),
        });
        exe.root_module.addImport("ecs", ecs_mod);
        b.installArtifact(exe);

        const run_step = b.step("run", "Run the application");
        const run_exe = b.addRunArtifact(exe);
        exe.linkLibrary(raylib_artifact);
        exe.root_module.addImport("raylib", raylib);
        exe.root_module.addImport("raygui", raygui);
        run_step.dependOn(&run_exe.step);
    }

    { // run the main test
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
        const run_test_step = b.step("test-main", "Run unit tests");
        const run_test = b.addRunArtifact(test_exe);
        test_exe.linkLibrary(raylib_artifact);
        test_exe.root_module.addImport("raylib", raylib);
        test_exe.root_module.addImport("raygui", raygui);

        test_exe.root_module.addImport("ecs", ecs_mod);
        run_test_step.dependOn(&run_test.step);
    }

    { // run the ecs test
        const ecs_test_exe = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/ecs.zig"),
                .target = t,
                .optimize = o,
            }),
            .test_runner = .{
                .mode = .simple,
                .path = b.path("test_runner.zig"),
            },
        });
        const run_ecs_test_step = b.step("test-ecs", "Run unit tests");
        const run_ecs_test = b.addRunArtifact(ecs_test_exe);
        ecs_test_exe.linkLibrary(raylib_artifact);
        ecs_test_exe.root_module.addImport("raylib", raylib);

        run_ecs_test_step.dependOn(&run_ecs_test.step);
    }
}
