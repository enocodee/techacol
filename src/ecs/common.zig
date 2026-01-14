const World = @import("World.zig");

const position = @import("common/position.zig");
const grid = @import("common/grid/mod.zig");

const rectangle = @import("common/rectangle.zig");
const circle = @import("common/circle.zig");

const schedule = @import("schedule.zig");
const schedules = schedule.schedules;

pub const Set = @import("system.zig").Set;
/// Set of all non-UI components
///
/// See `ui.UiRenderSet` for UI components
pub const RenderSet = Set{ .name = "render" };

// Shape components
pub const Rectangle = rectangle.Rectangle;
pub const Circle = circle.Circle;
pub const CircleBundle = circle.Bundle;

// Other components
pub const Grid = grid.Grid;
pub const InGrid = grid.InGrid;
pub const Position = position.Position;
pub const Text = @import("common/Text.zig");
pub const TextBundle = Text.Bundle;

/// # Addons:
/// + Add the main scheduling.
/// + Add the render scheduling.
/// + Extract & render functions for common components
/// automatically.
///
pub const CommonModule = struct {
    pub fn build(w: *World) void {
        _ = w
            .addModules(&.{
                schedule.main_schedule_mod,
                schedule.render_schedule_mod,
            })
            .addModules(&.{
                @import("ui.zig"),
            })
            .addSystemsWithConfig(.render, schedules.update, .{
            rectangle.render,
            grid.render,
            circle.render,
            Text.render,
        }, .{ .in_sets = &.{RenderSet} });
    }
};

pub const Children = struct {
    id: @import("Entity.zig").ID,
};
