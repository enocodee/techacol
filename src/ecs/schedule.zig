//! This module exports all thing related to scheduling in `ecs`.
//!
//! Exported:
//! * Label
//! * Graph
//! * Scheduler
//! * schedules
//! * main_schedule_mod (used in `CommonModule`):
const Resource = @import("resource.zig").Resource;
const World = @import("World.zig");

pub const Label = @import("schedule/label.zig").Label;
pub const Graph = @import("schedule/Graph.zig");
pub const Scheduler = @import("schedule/Scheduler.zig");

/// All schedule labels are pre-defined in the `ecs`.
///
/// See `main_schedule_mod` for pre-customization of schedules.
pub const schedules = struct {
    /// The schedule should be run first of all whenever
    /// frame begins.
    /// The default entrypoint for schedules.
    pub const entry = Label.init("entry");

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
            .addSchedule(schedules.startup)
            .addSchedule(schedules.update)
            .addSchedule(schedules.deinit)
            .addResource(MainScheduleOrder, .{})
            .addSystem(schedules.entry, run)
            .addSystem(schedules.deinit, endFrame);
    }
};
