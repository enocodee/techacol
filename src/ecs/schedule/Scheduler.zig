//! A scheduler who collects and run all schedules by order
//! in the application.
//! TODO: Graph cache for schedules (notify when it need to be reset via `Event`)
const std = @import("std");
const ScheduleLabel = @import("label.zig").Label;

const Scheduler = @This();

labels: std.StringHashMapUnmanaged(ScheduleLabel) = .{},

pub fn deinit(
    self: *Scheduler,
    alloc: std.mem.Allocator,
) void {
    var value_iter = self.labels.valueIterator();
    while (value_iter.next()) |label| {
        label.deinit(alloc);
    }
    self.labels.deinit(alloc);
}

/// This function can cause to `panic` due to out of memory.
pub fn addSchedule(
    self: *Scheduler,
    alloc: std.mem.Allocator,
    schedule: ScheduleLabel,
) void {
    self
        .labels
        .put(alloc, schedule._label, schedule) catch @panic("OOM");
}

/// Run a schedule
pub fn runSchedule(
    self: Scheduler,
    alloc: std.mem.Allocator,
    w: *@import("../World.zig"),
    label: ScheduleLabel,
) !void {
    const sched = try self.getLabel(label);
    const system_node_ids = try sched.schedule(alloc);
    defer alloc.free(system_node_ids);

    for (system_node_ids) |id| {
        try sched.run(w, id);
    }
}

pub fn getLabel(
    self: *const Scheduler,
    label: ScheduleLabel,
) !ScheduleLabel {
    return self
        .labels
        .get(label._label) orelse
        error.ScheduleNotFound;
}

pub fn getLabelPtr(
    self: *const Scheduler,
    label: ScheduleLabel,
) !*ScheduleLabel {
    return self
        .labels
        .getPtr(label._label) orelse
        error.ScheduleNotFound;
}

pub fn addSystem(
    self: *Scheduler,
    schedule_label: @TypeOf(.enum_literal),
    comptime system_fn: anytype,
) void {
    const label = self.getLabelPtr(
        @tagName(schedule_label),
    ) orelse @panic("schedule not found"); // NOTE: this is intended :)

    label.addSystemWithConfig(self.alloc, system_fn) catch @panic("OOM");
}
