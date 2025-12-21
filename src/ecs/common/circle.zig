const std = @import("std");
const rl = @import("raylib");

const World = @import("../World.zig");
const Position = @import("position.zig").Position;

const QueryToRender = @import("utils.zig").QueryToRender;

pub const Bundle = struct {
    circle: Circle,
    pos: Position,
};

pub const Circle = struct {
    radius: i32,
    color: rl.Color,
};

pub fn render(queries: QueryToRender(&.{ Position, Circle })) !void {
    for (queries.many()) |query| {
        const pos, const cir = query;
        rl.drawCircle(
            pos.x,
            pos.y,
            @floatFromInt(cir.radius),
            cir.color,
        );
    }
}
