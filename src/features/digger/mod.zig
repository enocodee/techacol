const systems = @import("systems.zig");
const scheds = @import("ecs").schedules;

const World = @import("ecs").World;

const DiggerBundle = @import("components.zig").DiggerBundle;
pub const Digger = @import("components.zig").Digger;

pub const move = @import("cmds/move.zig");
pub const check = @import("cmds/check.zig");

pub fn build(w: *World) void {
    _ = w
        .addSystem(.system, scheds.startup, spawn)
        .addSystem(.system, scheds.update, systems.updatePos);
}

pub fn spawn(w: *World) !void {
    _ = w.spawnEntity(.{
        DiggerBundle{
            .digger = .{ .idx_in_grid = .{ .r = 0, .c = 0 } },
            .shape = .{ .circle = .{ .radius = 10, .color = .red }, .pos = .{ .x = 0, .y = 0 } },
            // TODO: grid entity should be `null` when initialized
            .in_grid = .{ .grid_entity = 0 },
        },
    });
}
