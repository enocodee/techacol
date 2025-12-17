const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const ecs_common = @import("ecs").common;
const resource = @import("../resources.zig");

const GameAssets = @import("../../../GameAssets.zig");
const Terminal = @import("../mod.zig").Terminal;
const Buffer = @import("../mod.zig").Buffer;
const World = @import("ecs").World;

const Grid = @import("ecs").common.Grid;
const Rectangle = ecs_common.Rectangle;
const Position = ecs_common.Position;
const Button = ecs_common.Button;

const Style = resource.Style;
const State = resource.State;

pub fn render(w: *World, _: std.mem.Allocator) !void {
    const style = try w.getResource(Style);
    const state = try w.getMutResource(State);

    const queries = try w.query(&.{ Grid, Buffer, Position, Rectangle, Terminal });
    const grid, const buf, const pos, const rec, _ = queries[0];

    drawLangSelection(state, rec, pos);
    try buf.drawCursor(grid, style, state);
    try buf.draw(grid, style);
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
