//! Manage anything in the application.
//!
//! # Features:
//! * Create and get new entity (entity_id).
//! * Lazy init storages.
//! * Set, get component by `entity_id`.
//! * Set, get resources.
//! * Query entities with specificied components.
//! * Modules (building blocks)
//!   + References to `Module` in Mach Engine or `Plugin` in Bevy.
const std = @import("std");
const rl = @import("raylib");
const component = @import("component.zig");
const resource = @import("resource.zig");

const ecs_util = @import("util.zig");
const ecs_common = @import("common.zig");
const _query = @import("query.zig");
const _system = @import("system.zig");
const schedule = @import("schedule.zig");

const ErasedComponentStorage = component.ErasedStorage;
const ComponentStorage = component.Storage;
const ErasedResourceType = resource.ErasedResource;
const Entity = @import("Entity.zig");
const Scheduler = schedule.Scheduler;
const scheds = schedule.schedules;
const System = _system.System;
const SystemConfig = System.Config;

const ScheduleLabel = @import("schedule.zig").Label;

const World = @This();

// TODO: add docs
pub const Module = struct {
    build_fn: *const fn (*World) void,
};

entity_count: usize = 0,
/// Each storage store data of a component.
/// # Example:
/// |--Velocity--|   |--Position--|
/// | x: 5, y: 2 |   | x: 5, y: 2 |
/// |------------|   |------------|
/// |x: 15, y: 2 |   |x: 15, y: 2 |
/// |------------|   |------------|
component_storages: std.AutoHashMap(u64, ErasedComponentStorage),
resources: std.AutoHashMap(u64, ErasedResourceType),
system_scheduler: Scheduler,
render_scheduler: Scheduler,
should_exit: bool = false,
/// The `long-live` allocator.
/// All things are allocated by this will persist until
/// the application terminates (in `world.deinit()`) or
/// freed manual allocations during application.
alloc: std.mem.Allocator,
/// The `short-live` allocator, per-frame allocations.
/// Should be used in `systems` to allocate each frame, and all
/// allocations are freed in bulk at frame end.
///
/// This allocator will be passed to the `systems` as a parameter.
arena: *std.heap.ArenaAllocator,

pub const SchedulerKind = enum {
    render,
    system,
};

/// This function can cause to `panic` due to out of memory
pub fn init(alloc: std.mem.Allocator) World {
    const arena = alloc.create(std.heap.ArenaAllocator) catch @panic("OOM");
    errdefer alloc.destroy(arena);
    arena.* = .init(alloc);

    return .{
        .arena = arena,
        .alloc = alloc,
        .component_storages = .init(alloc),
        .resources = .init(alloc),
        .system_scheduler = Scheduler.initWithEntrySchedule(alloc) catch @panic("OOM"),
        .render_scheduler = Scheduler.initWithEntrySchedule(alloc) catch @panic("OOM"),
    };
}

/// Elements will be `deinit`:
/// - Component storages.
/// - Resources.
/// - List of `systems`.
/// - Components in storages which have `deinit()`.
pub fn deinit(self: *World) void {
    var storage_iter = self.component_storages.iterator();
    while (storage_iter.next()) |entry| {
        entry.value_ptr.*.deinit_fn(self.*, self.alloc);
    }

    var resource_iter = self.resources.iterator();
    while (resource_iter.next()) |entry| {
        entry.value_ptr.*.deinit_fn(self.*, self.alloc);
    }

    self.component_storages.deinit();
    self.resources.deinit();

    self.system_scheduler.deinit(self.alloc);
    self.render_scheduler.deinit(self.alloc);

    self.arena.deinit();
    self.alloc.destroy(self.arena);
}

pub fn newEntity(self: *World) Entity.ID {
    const id = self.entity_count;
    self.entity_count += 1;
    return id;
}

/// If an component has the suffix `Bundle` at the end of its name,
/// it will be treated as a bundle.
pub fn spawnEntity(
    self: *World,
    values: anytype,
) Entity {
    const T = ecs_util.Deref(@TypeOf(values));
    const id = self.newEntity();

    inline for (std.meta.fields(T)) |f| {
        self.extractComponent(id, f.type, @field(values, f.name));
    }

    return .{
        .id = id,
        .world = self,
    };
}

// TODO: despawnEntity()

fn extractComponent(
    self: *World,
    id: Entity.ID,
    comptime T: type,
    comp: T,
) void {
    const ComponentType = @TypeOf(comp);

    if (comptime std.mem.endsWith(u8, @typeName(ComponentType), "Bundle")) {
        std.log.debug("extract bundle {s}", .{@typeName(ComponentType)});
        self.extractBundleComponent(id, T, comp);
    } else {
        self.setComponent(id, ComponentType, comp);
    }
}

/// Flatten all components in `Bundle` and add to the entity
fn extractBundleComponent(
    self: *World,
    id: Entity.ID,
    comptime T: type,
    bundle: T,
) void {
    if (@typeInfo(@TypeOf(bundle)) != .@"struct")
        @panic("Expected a tuple or struct for a bundle, found " ++ @typeName(@TypeOf(bundle)));

    const comps = @typeInfo(@TypeOf(bundle)).@"struct".fields;
    inline for (comps) |f| {
        self.extractComponent(id, f.type, @field(bundle, f.name));
    }
}

pub fn addResource(self: *World, comptime T: type, value: T) *World {
    self.setResource(T, value);
    return self;
}

/// This function can cause to `panic` due to out of memory
pub fn setResource(self: *World, comptime T: type, value: T) void {
    const resource_ptr = self.alloc.create(T) catch @panic("OOM");
    resource_ptr.* = value;

    const hash = std.hash_map.hashString(@typeName(T));
    self.resources.put(hash, .{
        .ptr = resource_ptr,
        .deinit_fn = struct {
            pub fn deinit(w: World, alloc: std.mem.Allocator) void {
                const ptr = ErasedResourceType.cast(w, T) catch unreachable;
                if (std.meta.hasFn(T, "deinit")) {
                    ptr.deinit(alloc);
                }
                alloc.destroy(ptr);
            }
        }.deinit,
    }) catch @panic("OOM");
}

pub const GetResourceError = error{
    /// `T` resource not found.
    ValueNotFound,
};
pub fn getResource(self: World, comptime T: type) !T {
    return (try ErasedResourceType.cast(self, T)).*;
}

pub fn getMutResource(self: World, comptime T: type) !*T {
    return ErasedResourceType.cast(self, T);
}

test "set & get resource" {
    const Settings = struct {
        music_volume: u8 = 100,
    };

    const App = struct {
        state: enum { start, running, stop } = .start,
    };

    const alloc = std.testing.allocator;
    var w: World = .init(alloc);
    defer w.deinit();

    _ = w
        .addResource(Settings, .{})
        .addResource(App, .{});

    const immutable_settings = try w.getResource(Settings);
    try std.testing.expectEqual(100, immutable_settings.music_volume);

    const mutable_app = try w.getMutResource(App);
    try std.testing.expectEqual(.start, mutable_app.state);
    mutable_app.*.state = .running;
    try std.testing.expectEqual(.running, mutable_app.state);
    mutable_app.*.state = .stop;
    try std.testing.expectEqual(.stop, mutable_app.state);
}

/// Create a new component `T` storage.
///
/// This function can cause to `panic` due to out of memory
pub fn newComponentStorage(
    self: *World,
    comptime T: type,
) *ComponentStorage(T) {
    const storage = self.alloc.create(ComponentStorage(T)) catch @panic("OOM");
    errdefer self.alloc.destroy(storage);
    storage.* = .{
        .data = .empty,
    };

    const hash = std.hash_map.hashString(@typeName(T));
    self.component_storages.put(hash, .{
        .ptr = storage,
        .deinit_fn = struct {
            pub fn deinit(w: World, alloc: std.mem.Allocator) void {
                const ptr = ErasedComponentStorage.cast(w, T) catch unreachable;
                ptr.deinit(alloc);
                alloc.destroy(ptr);
            }
        }.deinit,
    }) catch @panic("OOM");

    std.log.debug("Add component - {s}", .{@typeName(T)});
    return ErasedComponentStorage.cast(self.*, T) catch unreachable;
}

/// Create the new storage if the storage of `T` component doesn't
/// existed.
///
/// If a component `type` is reassigned, it will be overwritten
/// the old value in the storage.
///
/// This function can cause to `panic` due to out of memory.
pub fn setComponent(
    self: *World,
    entity_id: Entity.ID,
    comptime T: type,
    component_value: T,
) void {
    // get the storage or create the new one
    const s = ErasedComponentStorage
        .cast(self.*, T) catch
        self.newComponentStorage(T);

    // Append the value of the component to data
    // list in the storage
    s.data.put(
        self.alloc,
        entity_id,
        component_value,
    ) catch @panic("OOM");
}

/// Get an entity from id
pub fn entity(self: *World, id: Entity.ID) Entity {
    return .{ .id = id, .world = self };
}

pub const GetComponentError = error{
    /// The storage of `T` component not found.
    StorageNotFound,
    /// `T` component of a specified entity not found.
    ValueNotFound,
};
pub fn getComponent(
    self: World,
    entity_id: Entity.ID,
    comptime T: type,
) GetComponentError!T {
    const s = try ErasedComponentStorage.cast(self, T);
    return s.data.get(entity_id) orelse {
        std.log.err("not found any value of `{s}` component of the entity (id: `{d}`).", .{ @typeName(T), entity_id });
        return GetComponentError.ValueNotFound;
    };
}

pub fn getMutComponent(
    self: World,
    entity_id: Entity.ID,
    comptime T: type,
) !*T {
    const s = try ErasedComponentStorage.cast(self, T);
    return s.data.getPtr(entity_id) orelse GetComponentError.ValueNotFound;
}

test "Init entities" {
    const alloc = std.testing.allocator;

    const Position = struct {
        x: i32,
        y: i32,
    };

    var world: World = .init(alloc);
    defer world.deinit();

    const entity_1 = world.newEntity();
    world.setComponent(entity_1, Position, .{ .x = 5, .y = 6 });

    const comp_value_1 = try world.getComponent(entity_1, Position);
    try std.testing.expect(comp_value_1.x == 5);
    try std.testing.expect(comp_value_1.y == 6);

    const entity_2 = world.newEntity();
    world.setComponent(entity_2, Position, .{ .x = 10, .y = 6 });

    const comp_value_2 = try world.getComponent(entity_2, Position);
    try std.testing.expect(comp_value_2.x == 10);
    try std.testing.expect(comp_value_2.y == 6);
}

/// This function can cause to `panic` due to the `schedule_label`
/// isn't in the application scheduler.
/// See more info of `ScheduleLabel` in `ecs.schedule.Label`.
pub fn addSystem(
    self: *World,
    scheduler_kind: SchedulerKind,
    schedule_label: ScheduleLabel,
    comptime system_fn: anytype,
) *World {
    self
        .getSchedulerPtr(scheduler_kind)
        .addSystem(self.alloc, schedule_label, system_fn);
    return self;
}

pub fn addSystems(
    self: *World,
    scheduler_kind: SchedulerKind,
    label: ScheduleLabel,
    comptime fns: anytype,
) *World {
    const T = ecs_util.Deref(@TypeOf(fns));
    if (@typeInfo(T) != .@"struct")
        @compileError("Expected a tuple or struct, found " ++ @typeName(T));

    inline for (0..std.meta.fields(T).len) |i| {
        _ = self.addSystem(scheduler_kind, label, fns[i]);
    }
    return self;
}

/// This function can cause to `panic` due to the `schedule_label`
/// isn't in the application scheduler.
/// See more info of `ScheduleLabel` in `ecs.schedule.Label`.
pub fn addSystemWithConfig(
    self: *World,
    scheduler_kind: SchedulerKind,
    schedule_label: ScheduleLabel,
    comptime system_fn: anytype,
    comptime config: SystemConfig,
) *World {
    self
        .getSchedulerPtr(scheduler_kind)
        .addSystemWithConfig(self.alloc, schedule_label, system_fn, config);

    return self;
}

pub fn addSystemsWithConfig(
    self: *World,
    scheduler_kind: SchedulerKind,
    label: ScheduleLabel,
    comptime fns: anytype,
    comptime config: SystemConfig,
) *World {
    const T = ecs_util.Deref(@TypeOf(fns));
    if (@typeInfo(T) != .@"struct")
        @compileError("Expected a tuple or struct, found " ++ @typeName(T));

    inline for (0..std.meta.fields(T).len) |i| {
        _ = self.addSystemWithConfig(scheduler_kind, label, fns[i], config);
    }
    return self;
}

pub fn addModules(self: *World, comptime types: []const type) *World {
    inline for (types) |T| {
        self.addModule(T);
    }
    return self;
}

pub fn addModule(self: *World, comptime T: type) void {
    std.log.debug("Add module - {s}", .{@typeName(T)});
    if (std.meta.hasFn(T, "build")) {
        T.build(self);
    } else {
        @panic("The module `{s}` doesn't have the `build` function!");
    }
}

pub fn addSchedule(
    self: *World,
    scheduler_kind: SchedulerKind,
    label: ScheduleLabel,
) *World {
    self
        .getSchedulerPtr(scheduler_kind)
        .addSchedule(self.alloc, label);

    return self;
}

pub fn getSchedulePtr(
    self: *World,
    scheduler_kind: SchedulerKind,
    label: ScheduleLabel,
) !*ScheduleLabel {
    return self
        .getSchedulerPtr(scheduler_kind)
        .getLabelPtr(label);
}

pub fn getSchedulerPtr(self: *World, kind: SchedulerKind) *Scheduler {
    return switch (kind) {
        .system => &self.system_scheduler,
        .render => &self.render_scheduler,
    };
}

pub fn getScheduler(self: World, kind: SchedulerKind) Scheduler {
    return switch (kind) {
        .system => self.system_scheduler,
        .render => self.render_scheduler,
    };
}

/// Configure system sets.
///
/// This function can cause to `panic` due to adding
/// an invalid schedule or out of memory.
pub fn configureSet(
    self: *World,
    scheduler_kind: SchedulerKind,
    comptime label: ScheduleLabel,
    comptime set: _system.Set,
    comptime config: _system.Set.Config,
) *World {
    const sched = self.getSchedulePtr(scheduler_kind, label) catch
        @panic("the `" ++ label._label ++ "` schedule not found");

    sched.addSetWithConfig(
        self.alloc,
        set,
        config,
    ) catch @panic("OOM");

    return self;
}

/// Run all systems of an schedule
pub fn runSchedule(
    self: *World,
    label: ScheduleLabel,
) !void {
    try self
        .system_scheduler
        .runSchedule(self.alloc, self, label);
}

/// Start drawing in raylib and run the `.entry` schedule
pub fn run(self: *World) !void {
    while (!self.should_exit) {
        try self.system_scheduler.runSchedule(self.alloc, self, Scheduler.entry);
        try self.render_scheduler.runSchedule(self.alloc, self, Scheduler.entry);
    }
}

pub fn query(
    self: World,
    comptime types: []const type,
) !_query.Query(types) {
    var query_executor: _query.Query(types) = .{};
    try query_executor.query(self);
    return query_executor;
}

test "query" {
    const Player = struct { name: []const u8 };
    const Monster = struct { name: []const u8 };
    const Position = struct { x: i32, y: i32 };
    const Velocity = struct { x: i32, y: i32 };

    const alloc = std.testing.allocator;
    var w: World = .init(alloc);
    defer w.deinit();

    _ = w.spawnEntity(.{
        Player{ .name = "test_player" },
        Position{ .x = 1, .y = 2 },
        Velocity{ .x = 1, .y = 2 },
    });

    _ = w.spawnEntity(.{
        Monster{ .name = "test_monster1" },
        Position{ .x = 1, .y = 2 },
        Velocity{ .x = 5, .y = 10 },
    });

    _ = w.spawnEntity(.{
        Monster{ .name = "test_monster2" },
        Position{ .x = 1, .y = 2 },
    });

    const queries = (try query(w, &.{ Position, *Velocity })).many();

    try std.testing.expect(queries.len == 2);

    // Get components
    const pos_0: Position, const vec_0: *Velocity = queries[0];
    try std.testing.expect(pos_0.x == 1);
    try std.testing.expect(pos_0.y == 2);
    try std.testing.expect(vec_0.x == 5);
    try std.testing.expect(vec_0.y == 10);

    const pos_1: Position, const vec_1: *Velocity = queries[1];
    try std.testing.expect(pos_1.x == 1);
    try std.testing.expect(pos_1.y == 2);
    try std.testing.expect(vec_1.x == 1);
    try std.testing.expect(vec_1.y == 2);
    //
    vec_1.*.x += 1; // changes value

    // get again to see if the value was changed
    const queries2 = (try query(w, &.{ Position, Velocity })).many();

    const pos_2: Position, const vec_2: Velocity = queries2[1];
    try std.testing.expect(pos_2.x == 1);
    try std.testing.expect(vec_2.x == 2);

    const player_queries = (try query(w, &.{ Player, *Position })).many();
    try std.testing.expectEqual(1, player_queries.len);

    const player, const player_pos = player_queries[0];
    player_pos.x += 1;
    try std.testing.expectEqualSlices(u8, "test_player", player.name);
    try std.testing.expectEqual(player_pos.x, 2);

    const monster_queries = (try query(w, &.{ Monster, Position })).many();
    try std.testing.expectEqual(2, monster_queries.len);

    const monster1, _ = monster_queries[0];
    const monster2, _ = monster_queries[1];

    try std.testing.expectEqualSlices(u8, "test_monster1", monster1.name);
    try std.testing.expectEqualSlices(u8, "test_monster2", monster2.name);
}
