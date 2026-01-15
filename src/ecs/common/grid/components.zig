const std = @import("std");
const rl = @import("raylib");

/// Because we spawn a grid as an entity so another entities
/// need which grid they are in via `InGrid`.
pub const InGrid = struct { grid_entity: @import("../../Entity.zig").ID };

/// # Examples:
/// * rows = 3, cols = 3
/// |--|--|--|
/// |1 |2 |3 |
/// |--|--|--|
/// |4 |5 |6 |
/// |--|--|--|
/// |7 |8 |9 |
/// |--|--|--|
///
/// # Definitions:
/// - **Symbol:** `E(r, c)` is the element at _r-th_ row, _c-th_ col.
/// _(i, j are started from 0)_
///   + ## Examples:
///     + `E(0, 0)` = 1
///     + `E(1, 2)` = 6
///
/// - **Symbol:** `I(E(r, c))` is the actual index of `E(0, 0)` in the grid.
// TODO:
// Grid should only draw lines, not block
// references to component hierarchy in `Bevy` if want to draw blocks
pub const Grid = struct {
    matrix: []Cell = &.{},
    num_of_cols: i32,
    num_of_rows: i32,
    cell_width: i32,
    cell_height: i32,
    /// * color of:
    /// + *lines* if `render_mode` is `.line`
    /// + *blocks* if `render_mode` is `.block`
    color: rl.Color,
    cell_gap: i32,
    render_mode: RenderMode,

    const RenderMode = enum { line, block, none };

    pub const Error = error{
        OverNumRow,
        OverNumCol,
    };

    pub const Cell = struct {
        /// The actual x position in pixels.
        /// col_idx * (cell_width + cell_gap)
        x: i32,
        /// The actual y position in pixels.
        /// row_idx * (cell_width + cell_gap)
        y: i32,
    };

    /// Init `num_of_rows` * `num_of_cols` cells.
    /// Each `cell` is a rectangle.
    /// This function should be called after the grid object is initialized to
    /// init its cells.
    ///
    /// If you wonder why I choose 1-dimension and not n-dimension. The anwser is that
    /// Im avoiding allocating more times and managing more array ptr.
    ///
    /// `|-| <-> |-| <-> |-|`
    /// `|4| <-> |5| <-> |6|`
    /// `|-| gap |-| gap |-|`
    /// `|7| <-> |8| <-> |9|`
    /// `|-| <-> |-| <-> |-|`
    pub fn initCells(
        self: *Grid,
        alloc: std.mem.Allocator,
        pos_start_x: i32,
        pos_start_y: i32,
    ) void {
        const matrix = alloc.alloc(Cell, @intCast(self.num_of_rows * self.num_of_cols)) catch @panic("OOM");

        for (0..@intCast(self.num_of_rows)) |r| {
            for (0..@intCast(self.num_of_cols)) |c| {
                matrix[c + r * @as(u32, @intCast(self.num_of_cols))] = .{
                    .x = pos_start_x + @as(i32, @intCast((c))) * (self.cell_width + self.cell_gap),
                    .y = pos_start_y + @as(i32, @intCast((r))) * (self.cell_height + self.cell_gap),
                };
            }
        }

        self.matrix = matrix;
    }

    pub fn deinit(self: *Grid, alloc: std.mem.Allocator) void {
        alloc.free(self.matrix);
    }

    /// - Because the matrix is an one dimension array, so the elements can
    /// be flatted: `[1, 2, 3, 4, 5, 6, 7, 8, 9]`
    ///
    /// - Get the actual index of E(0, 0) in the grid by the general formula:
    ///   `I(E(r, c)) = r-th + c-th * num_of_cols`
    /// # Examples
    /// + I(E(0, 0)) = 0 + 0 * 3 = 0 => grid[0]
    ///      `v`
    ///  => `[1, 2, 3 , 4, 5, 6, 7, 8, 9]`
    ///      `v`
    ///  =>`|--|--|--|`
    ///   `>|1*|2 |3 |`
    ///    `|--|--|--|`
    ///    `|4 |5 |6 |`
    ///    `|--|--|--|`
    ///    `|7 |8 |9 |`
    ///    `|--|--|--|`
    ///
    /// + I(E(1, 0)) = 0 + 1 * 3 = 3 => grid[3]
    ///                 `v`
    ///   => `[1, 2, 3 , 4, 5, 6, 7, 8, 9]`
    ///       `v`
    ///   =>`|--|--|--|`
    ///     `|1 |2 |3 |`
    ///     `|--|--|--|`
    ///    `>|4*|5 |6 |`
    ///     `|--|--|--|`
    ///     `|7 |8 |9 |`
    ///     `|--|--|--|`
    ///
    /// + I(E(2, 1)) = 1 + 2 * 3 = 7 => grid[7]
    ///                            `v`
    ///   => `[1, 2, 3, 4, 5, 6, 7, 8, 9]`
    ///          `v`
    ///   =>`|--|--|--|`
    ///     `|1 |2 |3 |`
    ///     `|--|--|--|`
    ///     `|4 |5 |6 |`
    ///     `|--|--|--|`
    ///    `>|7 |8*|9 |`
    ///     `|--|--|--|`
    pub fn getActualIndex(self: Grid, r: i32, c: i32) !usize {
        if (r > self.num_of_rows - 1) return Error.OverNumRow;
        if (c > self.num_of_cols - 1) return Error.OverNumCol;
        return @intCast(c + r * self.num_of_cols);
    }

    test "get actual position in the grid" {
        const alloc = std.testing.allocator;
        var grid: Grid = .{
            .num_of_rows = 3,
            .num_of_cols = 3,
            .cell_height = 1,
            .cell_width = 1,
            .cell_gap = 1,
            .color = .blank,
            .render_mode = .none,
        };
        grid.initCells(alloc, 0, 0);
        defer grid.deinit(alloc);

        const pos1 = try grid.getActualIndex(0, 0);
        try std.testing.expectEqual(0, pos1);
        try std.testing.expectEqual(0, grid.matrix[pos1].x); // 0 * (1 + 1)
        try std.testing.expectEqual(0, grid.matrix[pos1].y); // 0 * (1 + 1)

        const pos2 = try grid.getActualIndex(1, 0);
        try std.testing.expectEqual(pos2, 3);
        try std.testing.expectEqual(0, grid.matrix[pos2].x); // 0 * (1 + 1)
        try std.testing.expectEqual(2, grid.matrix[pos2].y); // 1 * (1 + 1)

        const pos3 = try grid.getActualIndex(1, 1);
        try std.testing.expectEqual(4, pos3);
        try std.testing.expectEqual(2, grid.matrix[pos3].x); // 1 * (1 + 1)
        try std.testing.expectEqual(2, grid.matrix[pos3].y); // 1 * (1 + 1)

        try std.testing.expectError(Error.OverNumCol, grid.getActualIndex(0, 4));
        try std.testing.expectError(Error.OverNumRow, grid.getActualIndex(4, 0));

        var grid2: Grid = .{
            .num_of_cols = 3,
            .num_of_rows = 2,
            .cell_height = 2,
            .cell_width = 2,
            .cell_gap = 1,
            .color = .blank,
            .render_mode = .none,
        };
        grid2.initCells(alloc, 0, 0);
        defer grid2.deinit(alloc);

        const pos4 = try grid2.getActualIndex(0, 2);
        try std.testing.expectEqual(2, pos4);
        try std.testing.expectEqual(6, grid2.matrix[pos4].x); // 2 * (2 + 1)
        try std.testing.expectEqual(0, grid2.matrix[pos4].y); // 0 * (2 + 1)

        const pos5 = try grid2.getActualIndex(1, 2);
        try std.testing.expectEqual(5, pos5);
        try std.testing.expectEqual(6, grid2.matrix[pos5].x); // 2 * (2 + 1)
        try std.testing.expectEqual(3, grid2.matrix[pos5].y); // 2 * (2 + 1)

        try std.testing.expectError(Error.OverNumRow, grid2.getActualIndex(2, 3));
        try std.testing.expectError(Error.OverNumRow, grid2.getActualIndex(3, 4));
    }
};
