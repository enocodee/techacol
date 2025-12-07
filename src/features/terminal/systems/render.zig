const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const ecs_common = @import("ecs").common;
const resource = @import("../resources.zig");

const GameAssets = @import("../../../GameAssets.zig");
const Terminal = @import("../mod.zig").Terminal;
const World = @import("ecs").World;

const Grid = @import("ecs").common.Grid;
const Rectangle = ecs_common.Rectangle;
const Position = ecs_common.Position;
const Button = ecs_common.Button;

const Buffer = resource.Buffer;
const Style = resource.Style;
const State = resource.State;

const Padding = struct {
    x: i32,
    y: i32,
};

pub fn render(w: *World, _: std.mem.Allocator) !void {
    const style = try w.getResource(Style);
    const buf = try w.getResource(Buffer);
    const state = try w.getMutResource(State);

    const queries = try w.query(&.{ Grid, Position, Rectangle, Terminal });
    const grid, const pos, const rec, _ = queries[0];

    drawLangSelection(state, rec, pos);
    drawContent(grid, buf.chars, style, .{ .x = 0, .y = 0 });
    drawCursor(grid, buf, state, style, .{ .x = 0, .y = 0 });
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

fn drawContent(grid: Grid, content: [:0]u8, style: Style, pad: Padding) void {
    for (content, 0..) |c, i| {
        if (c != 0 and c != 13) {
            const real_pos = grid.matrix[i];

            rl.drawTextEx(
                style.font,
                rl.textFormat("%c", .{c}),
                .init(
                    @floatFromInt(real_pos.x + pad.x),
                    @floatFromInt(real_pos.y + pad.y),
                ),
                @floatFromInt(style.font_size),
                0,
                .white,
            );
        }
    }
}

fn drawCursor(
    grid: Grid,
    buf: Buffer,
    state: *State,
    style: Style,
    pad: Padding,
) void {
    if (state.is_focused) {
        state.*.frame_counter += 1;
    } else {
        state.*.frame_counter = 0;
    }

    const real_pos = grid.matrix[@intCast(buf.char_count)];

    if (state.is_focused) { // blink
        if (((state.*.frame_counter / 20) % 2) == 0) {
            rl.drawText("|", real_pos.x + pad.x, real_pos.y + pad.y, style.font_size, .white);
        }
    }
}
