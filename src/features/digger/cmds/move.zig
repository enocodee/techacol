const std = @import("std");
const ecs_common = @import("ecs").common;

const Interpreter = @import("../../interpreter/Interpreter.zig");

const World = @import("ecs").World;

const Position = ecs_common.Position;
const Grid = ecs_common.Grid;
const InGrid = ecs_common.InGrid;
const Digger = @import("../components.zig").Digger;

pub const MoveDirection = enum { up, down, left, right };

fn move(pos: *Digger.IndexInGrid, grid: Grid, direction: MoveDirection) void {
    switch (direction) {
        .up => {
            if (pos.r - 1 >= 0)
                pos.r -= 1;
        },
        .down => {
            if (pos.r + 1 < grid.num_of_rows)
                pos.r += 1;
        },
        .left => {
            if (pos.c - 1 >= 0)
                pos.c -= 1;
        },
        .right => {
            if (pos.c + 1 < grid.num_of_cols)
                pos.c += 1;
        },
    }
}

/// move the first digger
pub fn control(w: *World, move_direction: MoveDirection) !void {
    var digger, const in_grid = (try w.query(&.{
        *Digger,
        InGrid,
    }))[0];
    const grid = try w.getComponent(in_grid.grid_entity, Grid);

    move(&digger.idx_in_grid, grid, move_direction);
}
