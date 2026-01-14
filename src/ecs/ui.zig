const rl = @import("raylib");
const World = @import("World.zig");
const Set = @import("system.zig").Set;
const QueryUiToRender = @import("ui/utils.zig").QueryUiToRender;
const RenderSet = @import("common.zig").RenderSet;
const scheds = @import("schedule.zig").schedules;

pub const UiRenderSet = Set{ .name = "ui_render" };

pub const components = struct {
    /// NOTE: rectangle style only now
    /// This is intended like CSS in the future.
    pub const UiStyle = struct {
        pos: struct {
            x: i32 = 0,
            y: i32 = 0,
        } = .{},
        width: u32 = 50,
        height: u32 = 50,
        bg_color: rl.Color = .blank,
        text: ?struct {
            font: rl.Font,
            content: [:0]const u8,
            x: i32 = 0,
            y: i32 = 0,
        } = null,
    };
};

fn render(queries: QueryUiToRender) !void {
    for (queries.many()) |q| {
        const ui_style: components.UiStyle = q[0];

        rl.drawRectangle(
            ui_style.pos.x,
            ui_style.pos.y,
            @intCast(ui_style.width),
            @intCast(ui_style.height),
            ui_style.bg_color,
        );

        if (ui_style.text) |txt| {
            rl.drawTextEx(
                txt.font,
                txt.content,
                .{
                    .x = @floatFromInt(ui_style.pos.x + txt.x),
                    .y = @floatFromInt(ui_style.pos.y + txt.y),
                },
                20,
                1,
                .black,
            );
        }
    }
}

pub fn build(w: *World) void {
    _ = w.addSystemWithConfig(
        .render,
        scheds.update,
        render,
        .{ .in_sets = &.{UiRenderSet} },
    );
}
