const std = @import("std");
const rl = @import("raylib");

const World = @import("../World.zig");
const Position = @import("position.zig").Position;

const QueryToRender = @import("utils.zig").QueryToRender;

pub const Rectangle = struct {
    width: i32,
    height: i32,
    color: rl.Color,
};

pub fn render(queries: QueryToRender(&.{ Position, Rectangle })) !void {
    for (queries.many()) |query| {
        const pos, const rec = query;
        rl.drawRectangle(
            pos.x,
            pos.y,
            rec.width,
            rec.height,
            rec.color,
        );
    }
}
