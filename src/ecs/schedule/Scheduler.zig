//! A scheduler who collects and run all schedules by order
//! in the application.
//! TODO: Graph cache for schedules (notify when it need to be reset via `Event`)
const std = @import("std");
const ScheduleLabel = @import("label.zig").Label;
const System = @import("../system.zig").System;

const Scheduler = @This();

labels: std.StringHashMapUnmanaged(ScheduleLabel) = .{},

/// The schedule should be run first of all whenever
/// frame begins.
/// The default entrypoint for schedules.
pub const entry = ScheduleLabel.init("entry");

pub fn initWithEntrySchedule(alloc: std.mem.Allocator) !Scheduler {
    var labels: std.StringHashMapUnmanaged(ScheduleLabel) = .{};
    try labels.put(alloc, entry._label, entry);
    return .{
        .labels = labels,
    };
}

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
    alloc: std.mem.Allocator,
    schedule_label: ScheduleLabel,
    comptime system_fn: anytype,
) void {
    const label = self.getLabelPtr(
        schedule_label,
    ) catch @panic("schedule not found"); // NOTE: this is intended :)

    label.addSystem(alloc, System.fromFn(system_fn)) catch @panic("OOM");
}

pub fn addSystemWithConfig(
    self: *Scheduler,
    alloc: std.mem.Allocator,
    schedule_label: ScheduleLabel,
    comptime system_fn: anytype,
    comptime config: System.Config,
) void {
    const label = self.getLabelPtr(
        schedule_label,
    ) catch @panic("schedule not found"); // NOTE: this is intended :)

    label.addSystemWithConfig(alloc, System.fromFn(system_fn), config) catch @panic("OOM");
}
