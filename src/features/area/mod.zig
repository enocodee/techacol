const std = @import("std");
const scheds = @import("ecs").schedules;

const SystemSet = @import("ecs").system.Set;
const Grid = @import("ecs").common.Grid;
const World = @import("ecs").World;

const Area = @import("components.zig").Area;

pub const spawning_set: SystemSet = .{ .name = "area_spawning" };

pub fn build(w: *World) void {
    _ = w
        .addSystemWithConfig(
        .system,
        scheds.startup,
        spawn,
        .{ .in_sets = &.{spawning_set} },
    );
}

const NUM_OF_COLS = 10;
const NUM_OF_ROWS = 10;

pub fn spawn(w: *World, alloc: std.mem.Allocator) !void {
    var grid: Grid = .{
        .cell_height = 50,
        .cell_width = 50,
        .num_of_cols = NUM_OF_COLS,
        .num_of_rows = NUM_OF_ROWS,
        .cell_gap = 1,
        .color = .blue,
        .render_mode = .block,
    };
    grid.initCells(alloc, 0, 0);

    _ = w.spawnEntity(.{ Area{}, grid });
}
