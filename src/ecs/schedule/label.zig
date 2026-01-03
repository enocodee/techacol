const std = @import("std");
const World = @import("../World.zig");
const System = @import("../system.zig").System;

const Graph = @import("Graph.zig");

/// A schedule label (or simply called the **schedule**) mark
/// a stage in the schedule and contains all systems need
/// to be run **(belong to)** that label.
pub const Label = struct {
    const LabeledSchedule = @This();

    /// The container that contains all systems in the schedule.
    /// Indexed by system node id in the graph.
    systems: std.ArrayList(System) = .empty,
    graph: Graph = .{},
    _label: []const u8,

    pub fn init(comptime _label: []const u8) Label {
        return .{ ._label = _label };
    }

    pub fn deinit(self: *LabeledSchedule, alloc: std.mem.Allocator) void {
        self.systems.deinit(alloc);
        self.graph.deinit(alloc);
    }

    pub fn addSystem(
        self: *LabeledSchedule,
        alloc: std.mem.Allocator,
        comptime system: anytype,
    ) !void {
        try self.systems.append(alloc, System.fromFn(system));
        try self.graph.add(alloc, .{ .id = self.graph.count });
    }

    /// Get all node in the graph after sorting for scheduling.
    ///
    /// See `Label.run()` to run a system by node id.
    pub fn schedule(self: LabeledSchedule) []*const Graph.Node {
        return self.graph.getTopoSort();
    }

    /// Run a system by `node` in the graph
    pub fn run(
        self: LabeledSchedule,
        w: *World,
        node: Graph.Node,
    ) !void {
        std.debug.assert(node.id < self.systems.items.len);

        try self
            .systems
            .items[node.id]
            .handler(w);
    }
};

test "add systems" {
    const H = struct {
        pub fn system1() !void {
            std.log.debug("System 1 is running!", .{});
        }
        pub fn system2() !void {
            std.log.debug("System 2 is running!", .{});
        }
        pub fn system3() !void {
            std.log.debug("System 3 is running!", .{});
        }
    };

    const alloc = std.testing.allocator;
    var world: World = .init(alloc);
    defer world.deinit();

    var test_label: Label = .init("test");
    defer test_label.deinit(alloc);

    // No chidren were added
    try test_label.addSystem(alloc, H.system1);
    try test_label.addSystem(alloc, H.system2);
    try test_label.addSystem(alloc, H.system3);

    const system_nodes = test_label.schedule();
    for (system_nodes, 0..) |node, i| {
        try std.testing.expectEqual(i, node.id);
        try test_label.run(&world, node.*);
    }

    // TODO: Added children
}
