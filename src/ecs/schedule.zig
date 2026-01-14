//! This module exports all thing related to scheduling in `ecs`.
//!
//! Exported:
//! * Label
//! * Graph
//! * Scheduler
//! * schedules
//! * main_schedule_mod (used in `CommonModule`):
//! * render_schedule_mod (used in `CommonModule`):
const rl = @import("raylib");
const Resource = @import("resource.zig").Resource;
const World = @import("World.zig");

const UiRenderSet = @import("ui.zig").UiRenderSet;
const RenderSet = @import("common.zig").RenderSet;

pub const Label = @import("schedule/label.zig").Label;
pub const Graph = @import("schedule/Graph.zig");
pub const Scheduler = @import("schedule/Scheduler.zig");

/// All schedule labels are pre-defined in the `ecs`.
///
/// See `main_schedule_mod` for pre-customization of schedules.
pub const schedules = struct {
    /// Start the application
    pub const startup = Label.init("startup");

    /// The main loop of the application
    pub const update = Label.init("update");

    /// Frame deinit
    pub const deinit = Label.init("deinit");
};

const MainScheduleOrder = struct {
    /// Just run once
    startup_labels: []const Label = &[_]Label{
        schedules.startup,
    },
    /// Run multiple times
    labels: []const Label = &[_]Label{
        schedules.update,
        schedules.deinit,
    },
    is_run_once: bool = false,
};

fn render(w: *World) !void {
    rl.beginDrawing();
    defer {
        rl.clearBackground(.white);
        rl.endDrawing();
    }

    try w
        .render_scheduler
        .runSchedule(w.alloc, w, schedules.update);
}

fn run(w: *World, orders_res: Resource(*MainScheduleOrder)) !void {
    const orders = orders_res.result;
    if (!orders.is_run_once) {
        for (orders.startup_labels) |label| {
            try w.runSchedule(label);
        }
        orders.*.is_run_once = true;
    }

    for (orders.labels) |label| {
        try w.runSchedule(label);
    }
}

fn endFrame(w: *World) !void {
    // reset the short-lived allocator
    _ = w.arena.reset(.free_all);
}

pub const render_schedule_mod = struct {
    pub fn build(w: *World) void {
        _ = w
            .addSchedule(.render, schedules.update)
            .configureSet(
                .render,
                schedules.update,
                UiRenderSet,
                .{ .after = &.{RenderSet} },
            )
            .addSystem(.render, Scheduler.entry, render);
    }
};

/// A standard schedule pre-defined in the application.
/// # Orders:
/// * Run only once the application starts:
/// `startup`
///         |
///         v
/// * Run within the application's main loop:
/// `update` -> `last`
pub const main_schedule_mod = struct {
    pub fn build(w: *@import("World.zig")) void {
        _ = w
            .addSchedule(.system, schedules.startup)
            .addSchedule(.system, schedules.update)
            .addSchedule(.system, schedules.deinit)
            .addResource(MainScheduleOrder, .{})
            .addSystem(.system, Scheduler.entry, run)
            .addSystem(.system, schedules.deinit, endFrame);
    }
};
