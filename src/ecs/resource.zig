const std = @import("std");
const utils = @import("util.zig");
const World = @import("World.zig");

/// A wrapper for automatically querying a specified resource.
pub fn Resource(comptime T: type) type {
    return struct {
        result: T = undefined,

        pub const is_mutable = @typeInfo(T) == .pointer;

        const TypedRes = @This();

        pub fn query(self: *TypedRes, w: *World) !void {
            if (is_mutable) {
                self.result = try w.getMutResource(utils.Deref(T));
            } else {
                self.result = try w.getResource(T);
            }
        }
    };
}

pub const ErasedResource = struct {
    ptr: *anyopaque,
    deinit_fn: *const fn (World, std.mem.Allocator) void,

    pub inline fn cast(w: World, comptime T: type) !*T {
        const hash = std.hash_map.hashString(@typeName(T));
        const value = w.resources.storages.get(hash) orelse return World.GetResourceError.ValueNotFound;
        return @ptrCast(@alignCast(value.ptr));
    }
};
