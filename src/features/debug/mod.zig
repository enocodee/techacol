// TODO: Move this to `ecs.common`
const rl = @import("raylib");
const scheds = @import("ecs").schedules;
const systems = @import("systems.zig");
const components = @import("components.zig");

const World = @import("ecs").World;
const Box = components.DebugBox;
const Info = components.DebugInfo;

pub fn build(w: *World) void {
    _ = w
        .addSystem(.system, scheds.startup, spawn)
        .addSystems(.system, scheds.update, .{
            systems.updateInfo,
        })
        .addSystemWithConfig(
        .render,
        scheds.update,
        systems.render,
        .{ .in_sets = &.{@import("ecs").ui.UiRenderSet} },
    );
}

pub fn spawn(w: *World) !void {
    _ = w.spawnEntity(
        .{
            Info{},
            Box{
                .x = 10,
                .y = rl.getScreenHeight() - 100,
                .font_size = 20,
                .width = 250,
                .item_height = 30,
            },
        },
    );
}
