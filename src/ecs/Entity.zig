const std = @import("std");
const common = @import("common.zig");
const utils = @import("util.zig");
const query_helper = @import("query.zig");

const World = @import("World.zig");

const Entity = @This();

id: ID,
world: *World,

pub const ID = usize;

const SpawnChildrenCallback = *const fn (Entity) anyerror!void;

pub fn withChildren(
    self: Entity,
    callback: SpawnChildrenCallback,
) !void {
    try callback(self);
}

/// Safety used in multi-threading mode
pub fn spawn(self: Entity, components: anytype) Entity {
    const child_id =
        self
            .world
            .spawnEntity(components)
            .id;

    try self.pushChildren(&[_]ID{child_id});
    return self;
}

/// Push children's entity id as components for the parent entity
pub fn pushChildren(
    self: Entity,
    child_ids: []const ID,
) !void {
    for (child_ids) |c_id| {
        try self
            .world
            .setComponent(self.id, common.Children, .{ .id = c_id });
    }
}

pub fn getComponents(
    self: Entity,
    comptime types: []const type,
) !std.meta.Tuple(types) {
    return (try query_helper.tuplesFromTypes(
        self.world.*,
        &.{self.id},
        types,
    ))[0];
}
