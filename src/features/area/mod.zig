const std = @import("std");
const systems = @import("systems.zig");
const scheds = @import("ecs").schedules;

const SystemSet = @import("ecs").system.Set;
const Grid = @import("ecs").common.Grid;
const TextBundle = @import("ecs").common.TextBundle;
const World = @import("ecs").World;
const Entity = @import("ecs").Entity;
const GameAssets = @import("../../GameAssets.zig");

const Area = @import("components.zig").Area;

pub const spawning_set: SystemSet = .{ .name = "area_spawning" };

pub fn build(w: *World) void {
    _ = w
        .addSystemWithConfig(
        scheds.startup,
        spawn,
        .{ .in_sets = &.{spawning_set} },
    );
}

const NUM_OF_COLS = 3;
const NUM_OF_ROWS = 3;

pub fn spawn(w: *World, alloc: std.mem.Allocator) !void {
    var grid: Grid = .{
        .cell_height = 100,
        .cell_width = 100,
        .num_of_cols = NUM_OF_COLS,
        .num_of_rows = NUM_OF_ROWS,
        .cell_gap = 5,
        .color = .blue,
        .render_mode = .block,
    };
    grid.initCells(alloc, 0, 0);

    _ = try w.spawnEntity(.{ Area{}, grid }).withChildren(struct {
        pub fn cb(parent: Entity) !void {
            const g = (try parent.getComponents(&.{Grid}))[0];
            const assets = try parent.world.getMutResource(GameAssets);
            const font = try assets.getMainFont();

            for (g.matrix, 0..) |cell, i| {
                _ = parent.spawn(&.{TextBundle{
                    .text = .init(font, .{
                        .allocated = try std.fmt.allocPrintSentinel(parent.world.alloc, "{d}", .{i}, 0),
                    }),
                    .pos = .{
                        .x = cell.x + @divTrunc(g.cell_width, 2) - 5,
                        .y = cell.y + @divTrunc(g.cell_width, 2) - 5,
                    },
                }});
            }
        }
    }.cb);
}
