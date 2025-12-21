const std = @import("std");
const rl = @import("raylib");
const resource = @import("../resources.zig");
const ecs = @import("ecs");
const ecs_common = ecs.common;
const input = @import("input.zig");

const Query = ecs.query.Query;
const Resource = ecs.query.Resource;
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
    res_state: Resource(*State),
    queries: Query(&.{ Position, Rectangle, Terminal }),
) !void {
    const state = res_state.result;
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

pub fn inFocused(
    alloc: std.mem.Allocator,
    res_state: Resource(State),
    queries: Query(&.{ *Buffer, Grid, Terminal }),
) !void {
    const buf, const grid, _ = queries.single();

    if (res_state.result.is_focused)
        try input.handleKeys(alloc, grid, buf);
}

pub fn inClickedRun(
    w: *World,
    res_state: Resource(State),
    child_queries: Query(&.{ @import("ecs").common.Children, Terminal }),
    buf_queries: Query(&.{ Buffer, Terminal }),
) !void {
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
        if (rl.isMouseButtonPressed(.left) and res_state.result.active) {
            const content = try buf.toString(w.alloc);
            defer w.alloc.free(content);

            try input.process(
                w,
                w.alloc,
                content,
                @enumFromInt(res_state.result.selected_lang),
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
