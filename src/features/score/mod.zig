const ecs = @import("ecs");
const ecs_common = ecs.common;

const systems = @import("systems.zig");

const Position = ecs_common.Position;
const Circle = ecs_common.Circle;
const InGrid = ecs_common.InGrid;
const Grid = ecs_common.Grid;
const World = ecs.World;

const Point = @import("components.zig").Point;

pub const Score = struct {
    amount: i32 = 0,
};

pub fn build(w: *World) void {
    _ = w
        .addResource(Score, .{})
        .addSystem(.startup, spawn)
        .addSystems(.update, &.{
        systems.updatePos,
        systems.updateScore,
    });
}

pub fn spawn(w: *World) !void {
    const grid = try w.getComponent(0, Grid);
    _ = w.spawnEntity(.{
        Position{},
        try Point.random(grid.num_of_cols, grid.num_of_rows),
        Circle{ .radius = 5, .color = .yellow },
        InGrid{ .grid_entity = 0 },
    });
}
