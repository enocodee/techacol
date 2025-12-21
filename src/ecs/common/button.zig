const std = @import("std");
const rl = @import("raylib");

const World = @import("../World.zig");
const Position = @import("position.zig").Position;
const Rectangle = @import("rectangle.zig").Rectangle;

const QueryToRender = @import("utils.zig").QueryToRender;

pub const Bundle = struct {
    btn: Button,
    rec: Rectangle,
    pos: Position,
};

pub const Button = struct {
    content: [:0]const u8,
    font: rl.Font,
};

pub fn render(queries: QueryToRender(&.{ Position, Rectangle, Button })) !void {
    if (queries.single()) |q| {
        const pos, const rec, const btn = q;

        const measure_text = rl.measureTextEx(btn.font, btn.content, 20, 1);
        const text_x = pos.x + @divTrunc((rec.width - @as(i32, @intFromFloat(measure_text.x))), 2);
        const text_y = pos.y + @divTrunc((rec.height - @as(i32, @intFromFloat(measure_text.y))), 2);

        // draw the title
        rl.drawTextEx(
            btn.font,
            btn.content,
            .{ .x = @floatFromInt(text_x), .y = @floatFromInt(text_y) },
            20,
            1,
            .black,
        );
    }
}
