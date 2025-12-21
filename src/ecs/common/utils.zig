const std = @import("std");

const Query = @import("../query.zig").Query;
const World = @import("../World.zig");

pub fn QueryToRender(comptime types: []const type) type {
    const TypedQuery = Query(types);
    return struct {
        result: TypedQuery.Result = &.{},

        const Self = @This();

        /// This function is the same with `World.query()`, but it
        /// return `null` if one of the storage of `components` not found.
        ///
        /// Used to extract all components of an entity and ensure they are
        /// existed to render.
        pub fn query(self: *Self, w: World) !void {
            var obj: TypedQuery = .{};
            if (obj.query(w)) {
                self.result = obj.result;
            } else |err| {
                switch (err) {
                    World.GetComponentError.StorageNotFound => {}, // ignore
                    else => return err,
                }
            }
        }

        pub fn many(self: Self) TypedQuery.Result {
            return self.result;
        }

        pub fn single(self: Self) ?TypedQuery.Tuple {
            return if (self.result.len <= 0) return null else return self.result[0];
        }
    };
}
