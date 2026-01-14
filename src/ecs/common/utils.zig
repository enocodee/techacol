const Query = @import("../query.zig").Query;
const World = @import("../World.zig");
const Without = @import("../query.zig").filter.Without;
const UiStyle = @import("../ui.zig").components.UiStyle;

/// A wrapper for automatically querying a specified
/// normal entity components that should be called in
/// `system.toHandler` .
///
/// See `ui.QueryUiToRender` for UI components.
pub fn QueryToRender(comptime types: []const type) type {
    const TypedQuery = Query(types ++ [_]type{Without(&.{UiStyle})});
    return struct {
        result: TypedQuery.Result = .{},

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

        pub fn many(self: Self) []TypedQuery.Tuple {
            return self.result.many();
        }

        pub fn single(self: Self) ?TypedQuery.Tuple {
            return self.result.singleOrNull();
        }
    };
}
