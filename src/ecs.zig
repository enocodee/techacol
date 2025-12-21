const component = @import("ecs/component.zig");

pub const ErasedComponentStorage = component.ErasedStorage;
pub const ComponentStorage = component.Storage;

pub const World = @import("ecs/World.zig");
pub const Entity = @import("ecs/Entity.zig");

pub const common = @import("ecs/common.zig");
pub const CommonModule = common.CommonModule;

pub const query = struct {
    pub const Query = @import("ecs/query.zig").Query;
    pub const QueryError = @import("ecs/query.zig").QueryError;

    pub const Resource = @import("ecs/resource.zig").Resource;
};

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
