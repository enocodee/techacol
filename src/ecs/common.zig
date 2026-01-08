const World = @import("World.zig");

const position = @import("common/position.zig");
const grid = @import("common/grid/mod.zig");
const button = @import("common/button.zig");

const rectangle = @import("common/rectangle.zig");
const circle = @import("common/circle.zig");

const schedules = @import("schedule.zig").schedules;

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
pub const Button = button.Button;
pub const ButtonBundle = button.Bundle;
pub const Text = @import("common/Text.zig");
pub const TextBundle = Text.Bundle;

/// # Addons:
/// + Add the main schedule.
/// + Extract & render functions for common components
/// automatically.
///
pub const CommonModule = struct {
    pub fn build(w: *World) void {
        _ = w
            .addModules(&.{@import("schedule.zig").main_schedule_mod})
            .addSystems(schedules.update, .{
            rectangle.render,
            button.render,
            grid.render,
            circle.render,
            Text.render,
        });
    }
};

pub const Children = struct {
    id: @import("Entity.zig").ID,
};
