const std = @import("std");
const rl = @import("raylib");
const ecs_common = @import("ecs").common;
const resources = @import("resources.zig");
const systems = @import("systems.zig");
const components = @import("components.zig");

const World = @import("ecs").World;
const Button = ecs_common.Button;
const Rectangle = ecs_common.Rectangle;
const Position = ecs_common.Position;
const Grid = ecs_common.Grid;
const State = resources.State;
const Style = resources.Style;

const GameAssets = @import("../../GameAssets.zig");
const Executor = @import("../command_executor/mod.zig").CommandExecutor;

pub const Buffer = components.Buffer;
pub const Terminal = components.Terminal;

pub fn build(w: *World) void {
    var assets = w.getMutResource(GameAssets) catch unreachable;
    const font = assets.getTerminalFont() catch @panic("Cannot load terminal font");

    _ = w
        .addResource(Style, .{ .font = font, .font_size = 20 })
        .addResource(State, .{})
        .addSystem(.startup, spawn)
        .addSystems(.update, &.{
        systems.input.execCmds,
        systems.status.inHover,
        systems.status.inWindowResizing,
        systems.status.inFocused,
        systems.status.inClickedRun,
        systems.status.inCmdRunning,
        systems.render.render,
    });
}

pub fn spawn(w: *World, _: std.mem.Allocator) !void {
    const style = try w.getResource(Style);
    const measure_font = rl.measureTextEx(
        style.font,
        "a",
        @floatFromInt(style.font_size),
        0,
    );

    const font_x: i32 = @intFromFloat(measure_font.x);
    const font_y: i32 = @intFromFloat(measure_font.y);

    // spawn the terminal background
    w.spawnEntity(&.{ Terminal, Buffer, Position, Rectangle, Grid }, .{
        .{},
        try .init(w.alloc),
        .{ .x = rl.getScreenWidth() - 300, .y = 10 },
        .{ .width = 250, .height = 350, .color = .black },
        .init(
            w.alloc,
            5 + rl.getScreenWidth() - 300, // x
            15, // y
            // TODO: remove fixed values
            16, // rows
            25, // cols
            font_x, // width
            font_y, // height
            .red,
            2, // gap
            .line,
        ),
    });

    // spawn RUN button
    w.spawnEntity(&.{ Terminal, Button, Position, Rectangle }, .{
        .{},
        .{ .content = "Run", .font = style.font },
        .{ .x = (rl.getScreenWidth() - 300), .y = 360 },
        .{ .width = 100, .height = 50, .color = .gray },
    });

    // the command executor
    w.spawnEntity(&.{ Terminal, Executor }, .{
        .{},
        .init(w.alloc),
    });
}
