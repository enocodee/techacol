const component = @import("ecs/component.zig");
const scheds = @import("ecs/schedule.zig").schedules;

pub const ErasedComponentStorage = component.ErasedStorage;
pub const ComponentStorage = component.Storage;

pub const World = @import("ecs/World.zig");
pub const Entity = @import("ecs/Entity.zig");

pub const common = @import("ecs/common.zig");
pub const CommonModule = common.CommonModule;

pub const ui = @import("ecs/ui.zig");

pub const query = struct {
    const _query = @import("ecs/query.zig");

    pub const Query = _query.Query;
    pub const QueryError = _query.QueryError;

    // filter
    pub const With = _query.filter.With;
    pub const Without = _query.filter.Without;

    pub const Resource = @import("ecs/resource.zig").Resource;
};

pub const schedules = struct {
    pub const startup = scheds.startup;
    pub const update = scheds.update;
    pub const deinit = scheds.deinit;
};

pub const system = struct {
    const _system = @import("ecs/system.zig");

    pub const Set = _system.Set;
};

test {
    @import("std").testing.refAllDeclsRecursive(@This());

    // NOTE: import for testing steps
    _ = @import("ecs/schedule.zig").Graph;
}
