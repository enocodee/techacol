const std = @import("std");
const ecs_common = @import("ecs").common;

const Position = ecs_common.Position;
const Circle = ecs_common.Circle;
const Grid = ecs_common.Grid;
const InGrid = ecs_common.InGrid;
const World = @import("ecs").World;

const Area = @import("../area/components.zig").Area;

pub const Digger = @import("components.zig").Digger;

const systems = @import("systems.zig");

pub const move = @import("cmds/move.zig");
pub const check = @import("cmds/check.zig");

pub fn build(w: *World) void {
    _ = w
        .addSystem(.startup, spawn)
        .addSystem(.update, systems.updatePos);
}

pub fn spawn(w: *World, _: std.mem.Allocator) !void {
    w.spawnEntity(
        &.{
            Digger,
            Circle,
            Position,
            InGrid,
        },
        .{
            .{ .idx_in_grid = .{ .r = 0, .c = 0 } },
            .{ .radius = 10, .color = .red },
            .{ .x = 0, .y = 0 },
            // TODO: grid entity should be `null` when initialized
            .{ .grid_entity = 0 },
        },
    );
}
