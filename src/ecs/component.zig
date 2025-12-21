const std = @import("std");
const ecs_util = @import("util.zig");
const World = @import("World.zig");
const EntityID = @import("Entity.zig").ID;

pub fn Storage(comptime T: type) type {
    return struct {
        data: std.AutoHashMapUnmanaged(EntityID, T),

        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            if (std.meta.hasFn(T, "deinit")) {
                var data_iter = self.data.valueIterator();
                std.log.debug("Total entries: {d} - {s}", .{ self.data.size, @typeName(T) });
                std.log.debug("Deinit component - {s}", .{@typeName(T)});
                while (data_iter.next()) |data| {
                    data.deinit(alloc);
                }
            }
            self.data.deinit(alloc);
        }
    };
}

/// Erased-type component storage
pub const ErasedStorage = struct {
    ptr: *anyopaque,
    deinit_fn: *const fn (World, std.mem.Allocator) void,

    pub inline fn cast(w: World, comptime T: type) !*Storage(T) {
        const Type = ecs_util.Deref(T);
        const hash = std.hash_map.hashString(@typeName(Type));
        const s = w.component_storages.get(hash) orelse {
            std.log.err("the storage of `{s}` not found", .{@typeName(T)});
            return World.GetComponentError.StorageNotFound;
        };
        return ErasedStorage.castFromPtr(s.ptr, Type);
    }

    pub inline fn castFromPtr(ptr: *anyopaque, comptime T: type) *Storage(T) {
        return @ptrCast(@alignCast(ptr));
    }
};
