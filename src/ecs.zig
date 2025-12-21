const component = @import("ecs/component.zig");

pub const ErasedComponentStorage = component.ErasedStorage;
pub const ComponentStorage = component.Storage;

pub const World = @import("ecs/World.zig");
pub const Entity = @import("ecs/Entity.zig");

pub const common = @import("ecs/common.zig");
pub const CommonModule = common.CommonModule;

pub const query = struct {
    const _query = @import("ecs/query.zig");

    pub const Query = _query.Query;
    pub const QueryError = _query.QueryError;

    // filter
    pub const With = _query.With;

    pub const Resource = @import("ecs/resource.zig").Resource;
};

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
