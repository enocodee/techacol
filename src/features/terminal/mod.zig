const rl = @import("raylib");
const ecs_common = @import("ecs").common;
const ecs_ui = @import("ecs").ui;
const scheds = @import("ecs").schedules;
const resources = @import("resources.zig");
const systems = @import("systems.zig");
const components = @import("components.zig");

const World = @import("ecs").World;
const Resourse = @import("ecs").query.Resource;
const Grid = ecs_common.Grid;
const State = resources.State;
const Style = resources.Style;
const UiStyle = ecs_ui.components.UiStyle;

const GameAssets = @import("../../GameAssets.zig");
const Executor = @import("../command_executor/mod.zig").CommandExecutor;

const TerminalBundle = components.TerminalBundle;

pub const Buffer = components.Buffer;
pub const RunButton = components.RunButton;
pub const Terminal = components.Terminal;

pub fn build(w: *World) void {
    var assets = w.getMutResource(GameAssets) catch unreachable;
    const font = assets.getTerminalFont() catch @panic("Cannot load terminal font");

    _ = w
        .addResource(Style, .{ .font = font, .font_size = 20 })
        .addResource(State, .{})
        .addSystem(.system, scheds.startup, spawn)
        .addSystems(.system, scheds.update, .{
            systems.input.execCmds,
            systems.status.inHover,
            systems.status.inWindowResizing,
            systems.status.inFocused,
            systems.status.inClickedRun,
            systems.status.inCmdRunning,
        }).addSystemWithConfig(
        .render,
        scheds.update,
        systems.render.render,
        .{ .in_sets = &.{ecs_ui.UiRenderSet} },
    );
}

pub fn spawn(w: *World, res_style: Resourse(Style)) !void {
    const style = res_style.result;
    const measure_font = rl.measureTextEx(
        style.font,
        "a",
        @floatFromInt(style.font_size),
        0,
    );

    const font_x: i32 = @intFromFloat(measure_font.x);
    const font_y: i32 = @intFromFloat(measure_font.y);

    var grid: Grid = .{
        .num_of_rows = 16,
        .num_of_cols = 25,
        .cell_gap = 2,
        .color = .red,
        .cell_width = font_x,
        .cell_height = font_y,
        .render_mode = .none,
    };
    grid.initCells(w.alloc, 5 + rl.getScreenWidth() - 300, 15);

    _ = try w.spawnEntity(.{
        UiStyle{
            .pos = .{ .x = rl.getScreenWidth() - 300, .y = 10 },
            .height = 360,
            .width = 300,
            .bg_color = .black,
        },
        TerminalBundle{
            .buffer = .{ .buf = try Buffer.init(w.alloc), .grid = grid },
            .executor = Executor.init(w.alloc),
        },
    }).withChildren(struct {
        pub fn cb(parent: @import("ecs").Entity) !void {
            const s = try parent.world.getResource(Style);

            _ = parent.spawn(.{
                UiStyle{
                    .pos = .{ .x = (rl.getScreenWidth() - 300), .y = 370 },
                    .width = 100,
                    .height = 50,
                    .bg_color = .gray,
                    .text = .{
                        .content = "Run",
                        .font = s.font,
                    },
                },
                RunButton{},
            });
        }
    }.cb);
}
