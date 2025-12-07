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

const ErasedComponentStorage = component.ErasedStorage;
const ComponentStorage = component.Storage;
const ErasedResourceType = resource.ErasedResource;

const World = @This();

pub const EntityID = usize;
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

pub fn newEntity(self: *World) EntityID {
    const id = self.entity_count;
    self.entity_count += 1;
    return id;
}

pub fn spawnEntity(
    self: *World,
    comptime types: []const type,
    values: std.meta.Tuple(types),
) void {
    const id = self.newEntity();

    inline for (types, 0..) |T, i| {
        try self.setComponent(id, T, values[i]);
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
    entity_id: EntityID,
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
pub const GetComponentError = error{
    /// The storage of `T` component not found.
    StorageNotFound,
    /// `T` component of a specified entity not found.
    ValueNotFound,
};
pub fn getComponent(
    self: World,
    entity_id: EntityID,
    comptime T: type,
) GetComponentError!T {
    const s = try ErasedComponentStorage.cast(self, T);
    return s.data.get(entity_id) orelse GetComponentError.ValueNotFound;
}

pub fn getMutComponent(
    self: World,
    entity_id: EntityID,
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

/// Matching enittiy ids between `l1` and `l2`.
/// The result will be written to l1 and the order of
/// elements following `l1`.
///
/// If one of lists is `null`, assign remaining value to `dest`.
fn findMatch(
    alloc: std.mem.Allocator,
    l1: *std.ArrayList(EntityID),
    l2: std.ArrayList(EntityID),
) !void {
    if (l2.items.len == 0) return;
    if (l1.items.len == 0) {
        l1.clearAndFree(alloc);
        try l1.appendSlice(alloc, l2.items);
        return;
    }

    var l: std.ArrayList(EntityID) = .empty;
    defer l.deinit(alloc);
    outer: for (l1.items) |it1| {
        for (l2.items) |it2| {
            if (it2 == it1) {
                try l.append(alloc, it1);
                continue :outer;
            }
        }
    }

    l1.clearAndFree(alloc);
    try l1.appendSlice(alloc, l.items);
}

test "find match" {
    const alloc = std.testing.allocator;
    var l1: std.ArrayList(EntityID) = .empty;
    defer l1.deinit(alloc);

    var buf2 = [_]EntityID{ 1, 2, 3, 6 };
    var l2: std.ArrayList(EntityID) = .empty;
    defer l2.deinit(alloc);
    try l2.appendSlice(alloc, &buf2);

    try findMatch(alloc, &l2, l1);
    try std.testing.expectEqualSlices(EntityID, &[_]EntityID{ 1, 2, 3, 6 }, l2.items);

    var buf3 = [_]EntityID{ 1, 3, 2, 7, 8 };
    var l3: std.ArrayList(EntityID) = .empty;
    defer l3.deinit(alloc);
    try l3.appendSlice(alloc, &buf3);

    var buf4 = [_]EntityID{ 1, 5, 2, 3, 6, 10, 2 };
    var l4: std.ArrayList(EntityID) = .empty;
    defer l4.deinit(alloc);
    try l4.appendSlice(alloc, &buf4);

    try findMatch(alloc, &l3, l4);
    try std.testing.expectEqualSlices(EntityID, &[_]EntityID{ 1, 3, 2 }, l3.items);

    try findMatch(alloc, &l2, l3);
    try std.testing.expectEqualSlices(EntityID, &[_]EntityID{ 1, 2, 3 }, l2.items);
}

// Return type of `getKeysOfMinStorage()`.
const KeyMin = struct {
    items: []EntityID,
    idx: usize,

    pub fn deinit(self: *KeyMin, alloc: std.mem.Allocator) void {
        alloc.free(self.items);
    }
};

/// Get all keys of a storage in `types`
/// which has the `fewest` elements.
fn getKeysOfMinStorage(self: World, comptime types: []const type) !KeyMin {
    const alloc = self.arena.allocator();
    // NOTE: always get the first component
    var min: u32 = std.math.maxInt(u32);
    var idx: usize = 0;

    // get the index of the storage
    inline for (types, 0..) |T, i| {
        const Type = ecs_util.Deref(T);
        const size = (try ErasedComponentStorage
            .cast(self, Type))
            .data
            .size;

        if (min >= size) {
            min = size;
            idx = i;
        }
    }

    var keys_list: std.ArrayList(u64) = .empty;

    // get the value of min
    inline for (types, 0..) |T, i| {
        if (idx == i) {
            const Type = ecs_util.Deref(T);
            var iter = (try ErasedComponentStorage
                .cast(self, Type))
                .data
                .keyIterator();

            while (iter.next()) |it| {
                try keys_list.append(alloc, it.*);
            }

            return .{
                .items = keys_list.items,
                .idx = idx,
            };
        }
    }

    unreachable;
}

test "get keys of min storage" {
    const Position = struct { x: i32, y: i32 };
    const Velocity = struct { x: i32, y: i32 };

    const alloc = std.testing.allocator;
    var w: World = .init(alloc);
    defer w.deinit();

    w.spawnEntity(&.{ Position, Velocity }, .{
        .{ .x = 1, .y = 2 },
        .{ .x = 1, .y = 2 },
    });

    w.spawnEntity(&.{ Position, Velocity }, .{
        .{ .x = 1, .y = 2 },
        .{ .x = 5, .y = 10 },
    });

    w.spawnEntity(&.{Position}, .{
        .{ .x = 1, .y = 2 },
    });

    const k1 = try w.getKeysOfMinStorage(&.{ Position, Velocity });

    try std.testing.expectEqual(1, k1.idx);
    try std.testing.expectEqualSlices(u64, &.{ 1, 0 }, k1.items);

    // add one more component
    const Weapon = struct { name: []const u8 };
    try w.setComponent(1, Weapon, .{ .name = "sword" });

    const k2 = try w.getKeysOfMinStorage(&.{ Position, Velocity, Weapon });

    try std.testing.expectEqual(2, k2.idx);
    try std.testing.expectEqualSlices(u64, &.{1}, k2.items);
}

pub const QueryError = error{OutOfMemory} || GetComponentError;
/// Get entities's components
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
pub fn query(
    self: World,
    comptime types: []const type,
) QueryError![]std.meta.Tuple(types) {
    const alloc = self.arena.allocator();
    // The temporarily list to contain entity ids from `types[index]`
    var temp_list: std.ArrayList(EntityID) = .empty;
    const min_storage = try self.getKeysOfMinStorage(types);
    // assign the storage which has the fewest elements first
    var result_list: std.ArrayList(EntityID) = .fromOwnedSlice(min_storage.items);

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
            try findMatch(alloc, &result_list, temp_list);

            // reset l1
            temp_list.clearAndFree(alloc);
        }
    }

    return self.tuplesFromTypes(result_list.items, types);
}

fn tuplesFromTypes(
    self: World,
    entities: []const EntityID,
    comptime types: []const type,
) ![]std.meta.Tuple(types) {
    const alloc = self.arena.allocator();
    var tuple_list: std.ArrayList(std.meta.Tuple(types)) = .empty;

    for (entities) |entity_id| {
        var tuple: std.meta.Tuple(types) = undefined;
        inline for (types, 0..) |T, i| {
            if (@typeInfo(T) == .pointer) {
                tuple[i] = try self.getMutComponent(entity_id, std.meta.Child(T));
            } else {
                if (T != EntityID)
                    tuple[i] = try self.getComponent(entity_id, T)
                else
                    tuple[i] = entity_id;
            }
        }
        try tuple_list.append(alloc, tuple);
    }

    return tuple_list.items;
}

test "query" {
    const Player = struct { name: []const u8 };
    const Monster = struct { name: []const u8 };
    const Position = struct { x: i32, y: i32 };
    const Velocity = struct { x: i32, y: i32 };

    const alloc = std.testing.allocator;
    var w: World = .init(alloc);
    defer w.deinit();

    w.spawnEntity(&.{ Player, Position, Velocity }, .{
        .{ .name = "test_player" },
        .{ .x = 1, .y = 2 },
        .{ .x = 1, .y = 2 },
    });

    w.spawnEntity(&.{ Monster, Position, Velocity }, .{
        .{ .name = "test_monster1" },
        .{ .x = 1, .y = 2 },
        .{ .x = 5, .y = 10 },
    });

    w.spawnEntity(&.{ Monster, Position }, .{
        .{ .name = "test_monster2" },
        .{ .x = 1, .y = 2 },
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
