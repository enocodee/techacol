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
const query_helper = @import("query_helper.zig");

const ErasedComponentStorage = component.ErasedStorage;
const ComponentStorage = component.Storage;
const ErasedResourceType = resource.ErasedResource;
const Entity = @import("Entity.zig");

const World = @This();

pub const System = struct {
    @"fn": Fn,
    order: ExecOrder,

    // TODO: make all args optional? I think the idea same with the dependency injection
    //      ex: aRandomSystemFn() -> fetch nothing
    //          aRandomSystemFn(allocator) -> just fetch allocator
    //          aRandomSystemFn(allocator, query_result) -> fetch allocator & query result
    //          aRandomSystemFn(allocator, resources) -> fetch allocator & resources
    pub const Fn = *const fn (*World, std.mem.Allocator) anyerror!void;
    pub const ExecOrder = enum {
        startup,
        update,
    };
};

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
systems: std.ArrayList(System),
resources: std.AutoHashMap(u64, ErasedResourceType),
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

/// This function can cause to `panic` due to out of memory
pub fn init(alloc: std.mem.Allocator) World {
    const arena = alloc.create(std.heap.ArenaAllocator) catch @panic("OOM");
    arena.* = .init(alloc);

    return .{
        .arena = arena,
        .alloc = alloc,
        .component_storages = .init(alloc),
        .systems = .empty,
        .resources = .init(alloc),
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
    self.systems.deinit(self.alloc);

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
    const type_info = @typeInfo(@TypeOf(values));
    if (type_info != .@"struct")
        @compileError("Expected a tuple or struct, found " ++ @typeName(@TypeOf(values)));
    const id = self.newEntity();

    const fields = type_info.@"struct".fields;
    inline for (fields) |f| {
        try self.extractComponent(id, f.type, @field(values, f.name));
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
) !void {
    const ComponentType = @TypeOf(comp);

    if (comptime std.mem.endsWith(u8, @typeName(ComponentType), "Bundle")) {
        std.log.debug("extract bundle {s}", .{@typeName(ComponentType)});
        try self.extractBundleComponent(id, T, comp);
    } else {
        try self.setComponent(id, ComponentType, comp);
    }
}

/// Flatten all components in `Bundle` and add to the entity
fn extractBundleComponent(
    self: *World,
    id: Entity.ID,
    comptime T: type,
    bundle: T,
) !void {
    if (@typeInfo(@TypeOf(bundle)) != .@"struct")
        @panic("Expected a tuple or struct for a bundle, found " ++ @typeName(@TypeOf(bundle)));

    const comps = @typeInfo(@TypeOf(bundle)).@"struct".fields;
    inline for (comps) |f| {
        try self.extractComponent(id, f.type, @field(bundle, f.name));
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
) !void {
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
    try world.setComponent(entity_1, Position, .{ .x = 5, .y = 6 });

    const comp_value_1 = try world.getComponent(entity_1, Position);
    try std.testing.expect(comp_value_1.x == 5);
    try std.testing.expect(comp_value_1.y == 6);

    const entity_2 = world.newEntity();
    try world.setComponent(entity_2, Position, .{ .x = 10, .y = 6 });

    const comp_value_2 = try world.getComponent(entity_2, Position);
    try std.testing.expect(comp_value_2.x == 10);
    try std.testing.expect(comp_value_2.y == 6);
}

pub fn addSystem(self: *World, order: System.ExecOrder, @"fn": System.Fn) *World {
    self.systems.append(self.alloc, .{
        .@"fn" = @"fn",
        .order = order,
    }) catch @panic("OOM");
    return self;
}

pub fn addSystems(
    self: *World,
    order: System.ExecOrder,
    fns: []const System.Fn,
) *World {
    for (fns) |f| {
        _ = self.addSystem(order, f);
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

pub fn run(self: *World) !void {
    for (self.systems.items) |system| {
        if (system.order == .startup)
            try system.@"fn"(self, self.arena.allocator());
    }

    while (!self.should_exit) {
        rl.beginDrawing();
        defer rl.endDrawing();

        for (self.systems.items) |system| {
            if (system.order == .update)
                try system.@"fn"(self, self.arena.allocator());
        }
        rl.clearBackground(.white);

        // free all things are allocated by `world.arena`
        _ = self.arena.reset(.free_all);
    }
}

pub const QueryError = error{OutOfMemory} || GetComponentError;
/// Fetch all entities that have **all** of the speicifed component types.
/// Return a slice of tuples, each tuple being a group of values of an entity.
///
/// # Examples:
/// ```zig
/// var result = try query(&.{Position, Velocity})
/// for (result) |entity| {
///     const pos: Position, const vec: Velocity = entity;
///     ...
/// }
/// ```
///
/// This function should be used in `systems` (called in every frame),
/// so we can ensure that all allocated things will be freed at the
/// end of the frame.
// TODO: query filter
pub fn query(
    self: World,
    comptime types: []const type,
) QueryError![]std.meta.Tuple(types) {
    const alloc = self.arena.allocator();
    // Temporary list containing entity ids for each component storage
    var temp_list: std.ArrayList(Entity.ID) = .empty;
    const min_storage = try query_helper.getKeysOfMinStorage(self, types);
    // init the result with the storage containing the fewest elements
    var result_list: std.ArrayList(Entity.ID) = .fromOwnedSlice(min_storage.items);

    inline for (types, 0..) |T, i| {
        // use label to control flow in comptime
        skip_min: {
            // skip the min_storage because its available
            // in the result list
            if (i == min_storage.idx) break :skip_min;

            const Type = ecs_util.Deref(T);
            const s = try ErasedComponentStorage.cast(self, Type);

            var data_iter = s.data.keyIterator();
            while (data_iter.next()) |it| {
                try temp_list.append(alloc, it.*);
            }
            try query_helper.findMatch(alloc, &result_list, temp_list);

            // reset l1
            temp_list.clearAndFree(alloc);
        }
    }

    return query_helper.tuplesFromTypes(self, result_list.items, types);
}

test "query" {
    const Player = struct { name: []const u8 };
    const Monster = struct { name: []const u8 };
    const Position = struct { x: i32, y: i32 };
    const Velocity = struct { x: i32, y: i32 };

    const alloc = std.testing.allocator;
    var w: World = .init(alloc);
    defer w.deinit();

    w.spawnEntity(.{
        Player{ .name = "test_player" },
        Position{ .x = 1, .y = 2 },
        Velocity{ .x = 1, .y = 2 },
    });

    w.spawnEntity(.{
        Monster{ .name = "test_monster1" },
        Position{ .x = 1, .y = 2 },
        Velocity{ .x = 5, .y = 10 },
    });

    w.spawnEntity(.{
        Monster{ .name = "test_monster2" },
        Position{ .x = 1, .y = 2 },
    });

    const queries = try query(w, &.{ Position, *Velocity });

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
    const queries2 = try query(w, &.{ Position, Velocity });

    const pos_2: Position, const vec_2: Velocity = queries2[1];
    try std.testing.expect(pos_2.x == 1);
    try std.testing.expect(vec_2.x == 2);

    const player_queries = try query(w, &.{ Player, *Position });
    try std.testing.expectEqual(1, player_queries.len);

    const player, const player_pos = player_queries[0];
    player_pos.x += 1;
    try std.testing.expectEqualSlices(u8, "test_player", player.name);
    try std.testing.expectEqual(player_pos.x, 2);

    const monster_queries = try query(w, &.{ Monster, Position });
    try std.testing.expectEqual(2, monster_queries.len);

    const monster1, _ = monster_queries[0];
    const monster2, _ = monster_queries[1];

    try std.testing.expectEqualSlices(u8, "test_monster1", monster1.name);
    try std.testing.expectEqualSlices(u8, "test_monster2", monster2.name);
}
