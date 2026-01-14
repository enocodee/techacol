const std = @import("std");
const rl = @import("raylib");
const schedules = @import("ecs").schedules;

const digger_mod = @import("features/digger/mod.zig");
const area_mod = @import("features/area/mod.zig");
const terminal_mod = @import("features/terminal/mod.zig");
const debug_mod = @import("features/debug/mod.zig");
const score_mod = @import("features/score/mod.zig");

const ecs = @import("ecs");
const World = ecs.World;

const GameAssets = @import("GameAssets.zig");

fn closeWindow(w: *World) !void {
    if (rl.windowShouldClose()) {
        w.should_exit = true;
    }
}

fn loop(alloc: std.mem.Allocator) !void {
    var world: World = .init(alloc);
    defer world.deinit();

    rl.setTargetFPS(60);

    try world
        .addModules(&.{ecs.CommonModule})
        .addResource(GameAssets, .{})
        .addSystems(.system, schedules.update, &.{closeWindow})
        .addModules(&.{
            area_mod,
            terminal_mod,
            digger_mod,
            score_mod,
            debug_mod,
        })
        .run();
}

pub fn main() !void {
    var base_alloc = std.heap.DebugAllocator(.{}).init;
    defer {
        if (base_alloc.deinit() == .leak) @panic("Leak memory have been detected!");
    }
    const alloc = base_alloc.allocator();

    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "Digger Replace");
    defer rl.closeWindow();

    try loop(alloc);
}

test {
    std.testing.refAllDecls(@This());
}
