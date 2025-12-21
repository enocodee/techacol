const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const ecs_common = ecs.common;

const World = ecs.World;
const Query = ecs.query.Query;
const Resource = ecs.query.Resource;
const Position = ecs_common.Position;
const Grid = ecs_common.Grid;
const InGrid = ecs_common.InGrid;

const Point = @import("components.zig").Point;
const Score = @import("mod.zig").Score;
const Digger = @import("../digger/mod.zig").Digger;

pub fn updatePos(w: *World, queries: Query(&.{ *Position, InGrid, Point })) !void {
    for (queries.many()) |query| {
        const pos, const in_grid, const digger = query;
        const idx_in_grid = digger.idx_in_grid;
        const grid = (try w.entity(in_grid.grid_entity).getComponents(&.{Grid}))[0];

        const pos_in_px = grid.matrix[@intCast(try grid.getActualIndex(idx_in_grid.r, idx_in_grid.c))];
        pos.x = pos_in_px.x + @divTrunc(grid.cell_width, 2);
        pos.y = pos_in_px.y + @divTrunc(grid.cell_width, 2);
    }
}

pub fn updateScore(
    w: *World,
    res_score: Resource(*Score),
    point_queries: Query(&.{ *Point, InGrid }),
    digger_queries: Query(&.{Digger}),
) !void {
    const score = res_score.result;
    const point: *Point, const in_grid = point_queries.single();
    const grid = (try w.entity(in_grid.grid_entity).getComponents(&.{Grid}))[0];

    const point_idx: Point.IndexInGrid = point.idx_in_grid;
    const digger_idx: Digger.IndexInGrid = (digger_queries.single()[0]).idx_in_grid;

    if (point_idx.c == digger_idx.c and
        point_idx.r == digger_idx.r)
    {
        score.*.amount += 1;
        point.* = try .random(grid.num_of_cols, grid.num_of_rows);
    }
}
