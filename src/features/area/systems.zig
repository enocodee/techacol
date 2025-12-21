const std = @import("std");
const ecs = @import("ecs");
const rl = @import("raylib");

const GameAssets = @import("../../GameAssets.zig");
const Query = ecs.query.Query;
const Resource = ecs.query.Resource;
const World = @import("ecs").World;
const Grid = @import("ecs").common.Grid;
const Area = @import("components.zig").Area;

pub fn render(
    res_assets: Resource(*GameAssets),
    queries: Query(&.{ Grid, Area }),
) !void {
    const assets = res_assets.result;
    const font = try assets.getMainFont();

    for (queries.many()) |query| {
        const grid = query[0]; // get "grid" field

        for (grid.matrix, 0..) |cell, i| {
            rl.drawTextEx(
                font,
                rl.textFormat("%d", .{i}),
                .{
                    .x = @floatFromInt(cell.x + @divTrunc(grid.cell_width, 2) - 5),
                    .y = @floatFromInt(cell.y + @divTrunc(grid.cell_width, 2) - 5),
                },
                @floatFromInt(font.baseSize - 9),
                0,
                .white,
            );
        }
    }
}
