const ecs_common = @import("ecs").common;

const World = @import("ecs").World;
const Grid = ecs_common.Grid;
const InGrid = ecs_common.InGrid;

const Digger = @import("../components.zig").Digger;

pub const EdgeDirection = enum { up, down, left, right };

fn isEdgeInternal(pos: *Digger.IndexInGrid, grid: Grid, direction: EdgeDirection) bool {
    const rows = grid.num_of_rows;
    const cols = grid.num_of_cols;

    return switch (direction) {
        .up => pos.r == 0, // the digger is in the first row of the grid
        .down => pos.r == rows - 1, // the digger is in the last row of the grid
        .left => pos.c == 0,
        .right => pos.c == cols - 1,
    };
}

/// move the first digger
pub fn isEdge(w: *World, edge_direciton: EdgeDirection) !bool {
    var digger, const in_grid = (try w.query(&.{
        *Digger,
        InGrid,
    })).single();
    const grid = try w.getComponent(in_grid.grid_entity, Grid);

    return isEdgeInternal(&digger.idx_in_grid, grid, edge_direciton);
}
