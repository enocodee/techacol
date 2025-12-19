const std = @import("std");
const ecs_util = @import("util.zig");

const ErasedComponentStorage = @import("component.zig").ErasedStorage;
const World = @import("World.zig");
const EntityID = @import("Entity.zig").ID;

/// Matching enittiy ids between `l1` and `l2`.
/// The result will be written to l1 and the order of
/// elements following `l1`.
///
/// If one of lists is `null`, assign remaining value to `dest`.
pub fn findMatch(
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
pub fn getKeysOfMinStorage(self: World, comptime types: []const type) !KeyMin {
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

    w.spawnEntity(.{
        Position{ .x = 1, .y = 2 },
        Velocity{ .x = 1, .y = 2 },
    });

    w.spawnEntity(.{
        Position{ .x = 1, .y = 2 },
        Velocity{ .x = 5, .y = 10 },
    });

    w.spawnEntity(.{
        Position{ .x = 1, .y = 2 },
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

pub fn tuplesFromTypes(
    w: World,
    entities: []const EntityID,
    comptime types: []const type,
) ![]std.meta.Tuple(types) {
    const alloc = w.arena.allocator();
    var tuple_list: std.ArrayList(std.meta.Tuple(types)) = .empty;

    for (entities) |entity_id| {
        var tuple: std.meta.Tuple(types) = undefined;
        inline for (types, 0..) |T, i| {
            if (@typeInfo(T) == .pointer) {
                tuple[i] = try w.getMutComponent(entity_id, std.meta.Child(T));
            } else {
                if (T != EntityID)
                    tuple[i] = try w.getComponent(entity_id, T)
                else
                    tuple[i] = entity_id;
            }
        }
        try tuple_list.append(alloc, tuple);
    }

    return tuple_list.items;
}
