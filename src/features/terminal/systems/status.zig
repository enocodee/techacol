const std = @import("std");
const rl = @import("raylib");
const resource = @import("../resources.zig");
const ecs_common = @import("ecs").common;
const input = @import("input.zig");

const World = @import("ecs").World;
const Terminal = @import("../mod.zig").Terminal;
const Buffer = @import("../mod.zig").Buffer;
const Executor = @import("../../command_executor/mod.zig").CommandExecutor;

const Rectangle = ecs_common.Rectangle;
const Position = ecs_common.Position;
const Button = ecs_common.Button;
const Grid = ecs_common.Grid;

const State = resource.State;

pub fn inHover(w: *World, _: std.mem.Allocator) !void {
    const queries = try w.query(&.{
        Position,
        Rectangle,
        Terminal,
    });
    const state = try w.getMutResource(State);
    const pos, const rec, _ = queries[0];

    const is_hovered = rl.checkCollisionPointRec(rl.getMousePosition(), .{
        .x = @floatFromInt(pos.x),
        .y = @floatFromInt(pos.y),
        .width = @floatFromInt(rec.width),
        .height = @floatFromInt(rec.height),
    });

    if (is_hovered) {
        rl.setMouseCursor(.ibeam);
        if (rl.isMouseButtonPressed(.left)) state.*.is_focused = true;
    } else {
        rl.setMouseCursor(.default);
        if (rl.isMouseButtonPressed(.left)) state.*.is_focused = false;
    }
}

pub fn inWindowResizing(w: *World, _: std.mem.Allocator) !void {
    const queries = try w.query(&.{ *Position, Terminal });
    const btn_queries = try w.query(&.{ *Position, Button });

    const pos, _ = queries[0];
    const btn_pos, _ = btn_queries[0];
    if (rl.isWindowResized()) {
        pos.x = rl.getScreenWidth() - 300;
        btn_pos.y = pos.y + 350;
        btn_pos.x = pos.x;
    }
}

pub fn inFocused(w: *World, _: std.mem.Allocator) !void {
    const state = try w.getMutResource(State);
    const buf, const grid, _ = (try w.query(&.{ *Buffer, Grid, Terminal }))[0];

    if (state.is_focused)
        try input.handleKeys(w.alloc, grid, buf);
}

pub fn inClickedRun(w: *World, _: std.mem.Allocator) !void {
    const state = try w.getResource(State);
    const pos, const rec, _, _ = (try w.query(&.{ Position, Rectangle, Button, Terminal }))[0];
    const buf, _ = (try w.query(&.{ Buffer, Terminal }))[0];

    if (rl.checkCollisionPointRec(
        rl.getMousePosition(),
        .{
            .x = @floatFromInt(pos.x),
            .y = @floatFromInt(pos.y),
            .width = @floatFromInt(rec.width),
            .height = @floatFromInt(rec.height),
        },
    )) {
        if (rl.isMouseButtonPressed(.left) and state.active) {
            const content = try buf.toString(w.alloc);
            defer w.alloc.free(content);

            try input.process(
                w,
                w.alloc,
                content,
                @enumFromInt(state.selected_lang),
            );
        }
    }
}

pub fn inCmdRunning(w: *World, _: std.mem.Allocator) !void {
    const state = try w.getMutResource(State);
    const executor = (try w.query(&.{ Executor, Terminal }))[0][0];
    const run_btn = (try w.query(&.{ *Button, Terminal }))[0][0];

    state.*.active = !executor.is_running;
    if (state.active) {
        run_btn.content = "Run";
    } else {
        run_btn.content = "Executing";
    }
}
