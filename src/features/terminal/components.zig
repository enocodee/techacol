const std = @import("std");
const rl = @import("raylib");

const digger = @import("../digger/mod.zig");
const utils = @import("utils.zig");

const World = @import("ecs").World;
const Grid = @import("ecs").common.Grid;
const Command = @import("../interpreter/command.zig").Command;
const State = @import("resources.zig").State;
const Style = @import("resources.zig").Style;

const QueryError = @import("ecs").World.QueryError;

pub const Terminal = struct {};

pub const Buffer = struct {
    // TODO: enhance the way to store `lines`
    // HACK: :)) this is very inefficent
    lines: Lines,
    cursor: struct {
        row: usize = 0,
        col: usize = 0,
    } = .{},
    total_line: usize = 0,

    const Lines = std.ArrayList(std.ArrayList(u8));

    pub fn init(alloc: std.mem.Allocator) !Buffer {
        var lines: Lines = .empty;
        // init the first line
        try lines.append(alloc, .empty);

        return .{
            .lines = lines,
        };
    }

    pub fn deinit(self: *Buffer, alloc: std.mem.Allocator) void {
        for (self.lines.items) |*line| {
            line.deinit(alloc);
        }
        self.lines.deinit(alloc);
    }

    pub fn draw(self: Buffer, grid: Grid, style: Style) !void {
        var col_in_grid: i32 = 0;
        var row_in_grid: i32 = 0;
        var count: i32 = 0;

        for (self.lines.items) |line| {
            count = 0;
            for (line.items) |c| {
                count += 1;
                if (count >= grid.num_of_cols) {
                    count = 1;
                    row_in_grid += 1;
                    col_in_grid = 0;
                }

                const pos = grid.matrix[try grid.getActualIndex(row_in_grid, col_in_grid)];

                rl.drawTextEx(
                    style.font,
                    rl.textFormat("%c", .{c}),
                    .init(
                        @floatFromInt(pos.x),
                        @floatFromInt(pos.y),
                    ),
                    @floatFromInt(style.font_size),
                    0,
                    .white,
                );

                col_in_grid += 1;
            }

            row_in_grid += 1;
            col_in_grid = 0;
        }
    }

    pub fn drawCursor(
        self: Buffer,
        grid: Grid,
        style: Style,
        /// take the pointer to increase or reset `frame_counter`
        state: *State,
    ) !void {
        if (state.is_focused) {
            state.*.frame_counter += 1;
        } else {
            state.*.frame_counter = 0;
        }

        const real_pos = grid.matrix[
            try grid.getActualIndex(
                @intCast(self.cursor.row),
                @intCast(self.cursor.col),
            )
        ];

        if (state.is_focused) { // blink
            if (((state.*.frame_counter / 20) % 2) == 0) {
                rl.drawText("|", real_pos.x, real_pos.y, style.font_size, .white);
            }
        }
    }

    /// The caller owns the the returned value memory.
    pub fn toString(self: Buffer, alloc: std.mem.Allocator) ![]const u8 {
        var list: std.ArrayList(u8) = .empty;
        defer list.deinit(alloc);

        for (self.lines.items) |line| {
            try list.appendSlice(alloc, line.items[0..line.items.len]);
            try list.append(alloc, ' ');
        }

        return list.toOwnedSlice(alloc);
    }

    /// Append a character to the current line and shift right the cursor.
    ///
    /// Asserts that the current line equals or less than the total line.
    pub fn insert(self: *Buffer, alloc: std.mem.Allocator, char: u8) !void {
        std.debug.assert(self.cursor.row <= self.total_line);

        const curr_idx = self.cursor.col;
        const curr_line = &self.lines.items[self.cursor.row];

        if (curr_idx == curr_line.*.items.len) { // at the last col
            try curr_line.append(alloc, char);
        } else { // at a random index which is not the last col
            try curr_line.ensureTotalCapacity(alloc, curr_line.items.len + 1);
            curr_line.items.len += 1;
            @memmove(
                curr_line.items[curr_idx + 1 .. curr_line.items.len],
                curr_line.items[curr_idx .. curr_line.items.len - 1],
            );

            curr_line.items[curr_idx] = char;
        }
        self.seek(.right);
    }

    /// Remove a character at current cursor position and **shift left
    /// the cursor**. If the cursor at the **first column**, it will move to
    /// the next character of the last character in the previous line.
    ///
    /// Asserts that the current line equals or less than the total line
    pub fn remove(self: *Buffer, alloc: std.mem.Allocator) !void {
        std.debug.assert(self.cursor.row <= self.total_line);
        if (self.cursor.row == 0 and self.lines.items[self.cursor.row].items.len == 0) return;

        if (self.cursor.col <= 0) {
            self.seek(.up);

            if (self.lines.items[self.cursor.row].items.len > 0) {
                const num_char_of_prev = self.lines.items[self.cursor.row].items.len;
                self.cursor.col = num_char_of_prev;
            } else {
                self.cursor.col = 0;
            }

            var line = self.lines.pop().?;
            line.deinit(alloc);
            self.total_line -= 1;
        } else {
            _ = self.lines.items[self.cursor.row].orderedRemove(self.cursor.col - 1);
            self.seek(.left);
        }
    }

    /// Add and move to the new line.
    pub fn newLine(self: *Buffer, alloc: std.mem.Allocator) !void {
        try self.lines.append(alloc, .empty);
        self.total_line += 1;
        self.cursor.row = self.lines.items.len - 1;
        self.cursor.col = 0;
    }

    /// Move the cursor with a direction.
    ///
    /// * Up: not move if `cursor.row == 0` (the first line)
    /// * Down: not move if `cursor.row > total line` (the last line)
    /// * Left: not move if `cursor.col == 0` (the first column)
    /// * Right: not move if `cursor.col >= num of characters in the line` (the last column)
    pub fn seek(self: *Buffer, dir: enum {
        up,
        down,
        left,
        right,
    }) void {
        switch (dir) {
            .up, .down => |up_or_down| {
                switch (up_or_down) {
                    .up => {
                        if (self.cursor.row > 0)
                            self.cursor.row -= 1;
                    },
                    .down => {
                        if (self.cursor.row < self.total_line)
                            self.cursor.row += 1;
                    },
                    else => unreachable,
                }

                // move cursor.col if neccessary
                if (self.cursor.col < self.lines.items[self.cursor.row].items.len) {
                    // do nothing
                } else if (self.lines.items[self.cursor.row].items.len > 0) {
                    // move to the last one of the previous line
                    const num_char_of_prev = self.lines.items[self.cursor.row].items.len;
                    self.cursor.col = num_char_of_prev;
                } else {
                    self.cursor.col = 0;
                }
            },
            .left => {
                if (self.cursor.col > 0)
                    self.cursor.col -= 1;
            },
            .right => {
                const curr_line = self.lines.items[self.cursor.row];

                if (self.cursor.col + 1 <= curr_line.items.len)
                    self.cursor.col += 1;
            },
        }
    }
};
