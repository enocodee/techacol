const std = @import("std");
const systems = @import("systems.zig");

const World = @import("ecs").World;
const Grid = @import("ecs").common.Grid;

const Area = @import("components.zig").Area;

pub fn build(w: *World) void {
    _ = w
        .addSystem(.startup, spawn)
        .addSystems(.update, &.{systems.render});
}

pub fn spawn(w: *World, _: std.mem.Allocator) !void {
    w.spawnEntity(
        .{ Area{}, Grid.init(
            w.alloc,
            0,
            0,
            3,
            3,
            100,
            100,
            .blue,
            5,
            .block,
        ) },
    );
}
