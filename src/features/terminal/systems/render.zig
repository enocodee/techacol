const rl = @import("raylib");
const rg = @import("raygui");
const ecs = @import("ecs");
const ecs_ui = @import("ecs").ui;
const ecs_common = ecs.common;
const resource = @import("../resources.zig");

const Terminal = @import("../mod.zig").Terminal;
const Buffer = @import("../mod.zig").Buffer;

const Query = ecs.query.Query;
const With = ecs.query.With;
const Resource = ecs.query.Resource;
const UiStyle = ecs_ui.components.UiStyle;
const Grid = @import("ecs").common.Grid;
const Rectangle = ecs_common.Rectangle;
const Position = ecs_common.Position;

const Style = resource.Style;
const State = resource.State;

pub fn render(
    res_style: Resource(Style),
    res_state: Resource(*State),
    queries: Query(&.{ Grid, Buffer, UiStyle, With(&.{Terminal}) }),
) !void {
    const state = res_state.result;
    const style = res_style.result;

    for (queries.many()) |q| {
        const grid, const buf, const ui_style: UiStyle = q;
        drawLangSelection(state, .{
            .width = @intCast(ui_style.width),
            .height = @intCast(ui_style.height),
            .color = ui_style.bg_color,
        }, .{
            .x = ui_style.pos.x,
            .y = ui_style.pos.y,
        });
        try buf.drawCursor(grid, style, state);
        try buf.draw(grid, style);
    }
}

fn drawLangSelection(state: *State, rec: Rectangle, pos: Position) void {
    const language_select_rec = rl.Rectangle.init(
        @floatFromInt(pos.x + rec.width - 100),
        @floatFromInt(pos.y - 10),
        100,
        10,
    );

    const is_selecting_lang: bool = rg.dropdownBox(
        language_select_rec,
        "plaintext;zig",
        &state.selected_lang,
        state.lang_box_is_opened,
    ) == 1;

    if (is_selecting_lang) {
        state.lang_box_is_opened = !state.lang_box_is_opened;
    }
}
