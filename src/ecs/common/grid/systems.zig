const std = @import("std");
const rl = @import("raylib");

const World = @import("../../World.zig");
const Grid = @import("components.zig").Grid;

const QueryToRender = @import("../utils.zig").QueryToRender;

pub fn renderGrid(queries: QueryToRender(&.{Grid})) !void {
    for (queries.many()) |q| {
        const grid = q[0];

        switch (grid.render_mode) {
            .line => renderGridLine(grid),
            .block => renderGridBlock(grid),
            .none => {},
        }
    }
}

fn renderGridBlock(grid: Grid) void {
    for (grid.matrix) |cell| {
        rl.drawRectangle(
            @intCast(cell.x),
            @intCast(cell.y),
            @intCast(grid.cell_width),
            @intCast(grid.cell_height),
            grid.color,
        );
    }
}

fn renderGridLine(grid: Grid) void {
    const rows: usize = @intCast(grid.num_of_rows);
    const cols: usize = @intCast(grid.num_of_cols);

    // draw vertical lines
    for (0..rows) |i| {
        const idx_x1 = cols * i;
        const idx_y1 = cols * (i + 1) - 1;

        rl.drawLine(
            grid.matrix[idx_x1].x,
            grid.matrix[idx_x1].y,
            grid.matrix[idx_y1].x,
            grid.matrix[idx_y1].y,
            grid.color,
        );
    }

    // draw horizontal lines
    for (0..cols) |i| {
        const idx_x1 = i;
        const idx_y1 = cols * (rows - 1) + i;

        rl.drawLine(
            grid.matrix[idx_x1].x,
            grid.matrix[idx_x1].y,
            grid.matrix[idx_y1].x,
            grid.matrix[idx_y1].y,
            grid.color,
        );
    }
}
