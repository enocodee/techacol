const std = @import("std");
const rl = @import("raylib");
const resource = @import("../resources.zig");
const ecs = @import("ecs");
const ecs_ui = @import("ecs").ui;
const ecs_common = ecs.common;
const input = @import("input.zig");

const Query = ecs.query.Query;
const With = ecs.query.With;
const Resource = ecs.query.Resource;
const World = ecs.World;
const UiStyle = ecs_ui.components.UiStyle;
const Terminal = @import("../mod.zig").Terminal;
const RunButton = @import("../mod.zig").RunButton;
const Buffer = @import("../mod.zig").Buffer;
const Executor = @import("../../command_executor/mod.zig").CommandExecutor;

const Children = ecs_common.Children;
const Grid = ecs_common.Grid;

const State = resource.State;

pub fn inHover(
    res_state: Resource(*State),
    queries: Query(&.{ UiStyle, With(&.{Terminal}) }),
) !void {
    const state = res_state.result;
    const ui_style = queries.single()[0];

    const is_hovered = rl.checkCollisionPointRec(rl.getMousePosition(), .{
        .x = @floatFromInt(ui_style.pos.x),
        .y = @floatFromInt(ui_style.pos.y),
        .width = @floatFromInt(ui_style.width),
        .height = @floatFromInt(ui_style.height),
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
    q_terminal_pos: Query(&.{ *UiStyle, With(&.{Terminal}) }),
    q_btn: Query(&.{ *UiStyle, With(&.{RunButton}) }),
) !void {
    const term_style = q_terminal_pos.single()[0];
    const btn_style = q_btn.single()[0];

    if (rl.isWindowResized()) {
        term_style.pos.x = rl.getScreenWidth() - 300;
        btn_style.pos.y = term_style.pos.y + 350;
        btn_style.pos.x = term_style.pos.x;
    }
}

pub fn inFocused(
    alloc: std.mem.Allocator,
    res_state: Resource(State),
    queries: Query(&.{ *Buffer, Grid, With(&.{Terminal}) }),
) !void {
    const buf, const grid = queries.single();

    if (res_state.result.is_focused)
        try input.handleKeys(alloc, grid, buf);
}

pub fn inClickedRun(
    w: *World,
    res_state: Resource(State),
    child_queries: Query(&.{ Children, With(&.{Terminal}) }),
    buf_queries: Query(&.{ Buffer, With(&.{Terminal}) }),
) !void {
    const child = child_queries.single()[0];
    // TODO: handle query children components
    const ui_style =
        (try w
            .entity(child.id)
            .getComponents(&.{UiStyle}))[0];

    const buf = buf_queries.single()[0];

    if (rl.checkCollisionPointRec(
        rl.getMousePosition(),
        .{
            .x = @floatFromInt(ui_style.pos.x),
            .y = @floatFromInt(ui_style.pos.y),
            .width = @floatFromInt(ui_style.width),
            .height = @floatFromInt(ui_style.height),
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
    state_res: Resource(*State),
    q_child: Query(&.{ Children, With(&.{Terminal}) }),
    q_executor: Query(&.{ Executor, With(&.{Terminal}) }),
) !void {
    const state = state_res.result;
    const executor = q_executor.single()[0];
    const child = q_child.single()[0];
    const ui_style_run_btn: *UiStyle = (try w.entity(child.id).getComponents(&.{*UiStyle}))[0];

    state.*.active = !executor.is_running;
    if (state.active) {
        ui_style_run_btn.text.?.content = "Run";
    } else {
        ui_style_run_btn.text.?.content = "Executing";
    }
}
