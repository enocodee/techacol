const ecs = @import("ecs");
const ecs_common = ecs.common;

const World = ecs.World;
const Query = ecs.query.Query;
const Position = ecs_common.Position;
const Grid = ecs_common.Grid;
const InGrid = ecs_common.InGrid;

const Digger = @import("mod.zig").Digger;

/// Draw all diggers
pub fn updatePos(
    w: *World,
    queries: Query(&.{ *Position, InGrid, Digger }),
) !void {
    for (queries.many()) |query| {
        const pos, const in_grid, const digger = query;
        const idx_in_grid = digger.idx_in_grid;
        // TODO: can we reduce boilerplate?
        const grid = (try w.entity(in_grid.grid_entity).getComponents(&.{Grid}))[0];

        const pos_in_px = grid.matrix[@intCast(try grid.getActualIndex(idx_in_grid.r, idx_in_grid.c))];
        pos.x = pos_in_px.x + @divTrunc(grid.cell_width, 2);
        pos.y = pos_in_px.y + @divTrunc(grid.cell_width, 2);
    }
}
