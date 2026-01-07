const std = @import("std");
const systems = @import("systems.zig");
const scheds = @import("ecs").schedules;

const SystemSet = @import("ecs").system.Set;
const World = @import("ecs").World;
const Grid = @import("ecs").common.Grid;

const Area = @import("components.zig").Area;

pub const spawning_set: SystemSet = .{ .name = "area_spawning" };

pub fn build(w: *World) void {
    _ = w
        .addSystemWithConfig(
            scheds.startup,
            spawn,
            .{ .in_sets = &.{spawning_set} },
        )
        .addSystems(scheds.update, .{systems.render});
}

pub fn spawn(w: *World, alloc: std.mem.Allocator) !void {
    var grid: Grid = .{
        .cell_height = 100,
        .cell_width = 100,
        .num_of_cols = 3,
        .num_of_rows = 3,
        .cell_gap = 5,
        .color = .blue,
        .render_mode = .block,
    };
    grid.initCells(alloc, 0, 0);

    _ = w.spawnEntity(.{ Area{}, grid });
}
