const World = @import("World.zig");
const Set = @import("system.zig").Set;

const Query = @import("query.zig").Query;
const With = @import("query.zig").With;

pub const UiRenderSet = Set{ .name = "ui_render" };

pub const components = struct {
    pub const UiStyle = struct {};
};

pub fn QueryUiToRender(comptime types: []type) type {
    const TypedQuery = Query(types ++ [_]type{With(&.{components.UiStyle})});
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
