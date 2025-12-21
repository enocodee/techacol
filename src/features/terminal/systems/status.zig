const std = @import("std");
const rl = @import("raylib");
const resource = @import("../resources.zig");
const ecs = @import("ecs");
const ecs_common = ecs.common;
const input = @import("input.zig");

const Query = ecs.query.Query;
const World = ecs.World;
const Terminal = @import("../mod.zig").Terminal;
const Buffer = @import("../mod.zig").Buffer;
const Executor = @import("../../command_executor/mod.zig").CommandExecutor;

const Children = ecs_common.Children;
const Rectangle = ecs_common.Rectangle;
const Position = ecs_common.Position;
const Button = ecs_common.Button;
const Grid = ecs_common.Grid;

const State = resource.State;

pub fn inHover(
    w: *World,
    queries: Query(&.{ Position, Rectangle, Terminal }),
) !void {
    const state = try w.getMutResource(State);
    const pos, const rec, _ = queries.single();

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

pub fn inWindowResizing(
    q_terminal_pos: Query(&.{ *Position, Terminal }),
    q_btn: Query(&.{ *Position, Button }),
) !void {
    const pos, _ = q_terminal_pos.single();
    const btn_pos, _ = q_btn.single();

    if (rl.isWindowResized()) {
        pos.x = rl.getScreenWidth() - 300;
        btn_pos.y = pos.y + 350;
        btn_pos.x = pos.x;
    }
}

pub fn inFocused(w: *World, queries: Query(&.{ *Buffer, Grid, Terminal })) !void {
    const state = try w.getMutResource(State);
    const buf, const grid, _ = queries.single();

    if (state.is_focused)
        try input.handleKeys(w.alloc, grid, buf);
}

pub fn inClickedRun(
    w: *World,
    child_queries: Query(&.{ @import("ecs").common.Children, Terminal }),
    buf_queries: Query(&.{ Buffer, Terminal }),
) !void {
    const state = try w.getResource(State);
    const child = child_queries.single()[0];
    // TODO: handle query children components
    const rec, const pos =
        (try w
            .entity(child.id)
            .getComponents(&.{ Rectangle, Position }));

    const buf, _ = buf_queries.single();

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

pub fn inCmdRunning(
    w: *World,
    q_child: Query(&.{ Children, Terminal }),
    q_executor: Query(&.{ Executor, Terminal }),
) !void {
    const state = try w.getMutResource(State);
    const executor = q_executor.single()[0];
    const child = q_child.single()[0];
    const run_btn = (try w.entity(child.id).getComponents(&.{*Button}))[0];

    state.*.active = !executor.is_running;
    if (state.active) {
        run_btn.content = "Run";
    } else {
        run_btn.content = "Executing";
    }
}
