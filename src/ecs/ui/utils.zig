const rl = @import("raylib");
const components = @import("../ui.zig").components;

const World = @import("../World.zig");
const Query = @import("../query.zig").Query;
const UiStyle = @import("../ui.zig").components.UiStyle;

const UiRenderSet = @import("../ui.zig").UiRenderSet;
const RenderSet = @import("../common.zig").RenderSet;

pub const QueryUiToRender = struct {
    const TypedQuery = Query(&[_]type{components.UiStyle});
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

fn render(queries: QueryUiToRender) void {
    for (queries.many()) |q| {
        const ui_style: UiStyle = q[0];

        rl.drawRectangle(
            ui_style.pos.x,
            ui_style.pos.y,
            ui_style.width,
            ui_style.width,
            ui_style.bg_color,
        );
    }
}

pub fn build(w: *World) void {
    _ = w
        .configureSet(.update, UiRenderSet, .{ .after = RenderSet })
        .addSystemWithConfig(.update, render, .{ .in_sets = UiRenderSet });
}
