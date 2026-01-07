const std = @import("std");
const system = @import("../system.zig");

const World = @import("../World.zig");
const SystemSet = system.Set;
const System = system.System;

const Graph = @import("Graph.zig");

/// A schedule label (or simply called the **schedule**) mark
/// a stage in the schedule and contains all systems need
/// to be run **(belong to)** that label.
pub const Label = struct {
    const LabeledSchedule = @This();

    /// The container that contains all data which contains
    /// systems and system sets in the schedule.
    ///
    /// Using `MultiArrayList` to make the index of elements
    /// are synced with node indexes of that elements in the
    /// graph. That means you can use `node.id` to access
    /// directly a `data`.
    ///
    /// Indexed by `Node.ID` in the graph.
    data: std.MultiArrayList(Data) = .empty,
    graph: Graph = .{},
    _label: []const u8,

    const Data = union(enum) {
        set: SystemSet,
        system: System,
    };

    pub fn init(comptime _label: []const u8) Label {
        return .{ ._label = _label };
    }

    pub fn deinit(self: *LabeledSchedule, alloc: std.mem.Allocator) void {
        self.data.deinit(alloc);
        self.graph.deinit(alloc);
    }

    pub fn addSystem(
        self: *LabeledSchedule,
        alloc: std.mem.Allocator,
        comptime sys: System,
    ) !void {
        _ = try self.putOneSystem(alloc, sys);
    }

    pub fn addSystemWithConfig(
        self: *LabeledSchedule,
        alloc: std.mem.Allocator,
        comptime sys: System,
        comptime config: System.Config,
    ) !void {
        var in_set_ids: std.ArrayList(Graph.Node.ID) = .empty;
        defer in_set_ids.deinit(alloc);

        // all sets must exist before the system
        inline for (config.in_sets) |set| {
            const id = try self.getOrPutSystemSet(alloc, set);
            try in_set_ids.append(alloc, id);
        }

        const id = self.graph.count;
        for (in_set_ids.items) |set_id| {
            try self.graph.addDep(alloc, set_id, .{ .system = id });
        }

        _ = try self.putOneSystem(alloc, sys);
    }

    /// Append a **system** to the list and add a
    /// **system** node to the graph.
    ///
    /// Return a node id
    fn putOneSystem(
        self: *LabeledSchedule,
        alloc: std.mem.Allocator,
        comptime sys: System,
    ) !Graph.Node.ID {
        try self.data.append(alloc, .{ .system = sys });
        return try self.graph.add(alloc, .system);
    }

    pub fn addSetWithConfig(
        self: *LabeledSchedule,
        alloc: std.mem.Allocator,
        comptime set: SystemSet,
        comptime config: SystemSet.Config,
    ) !void {
        // ensure all `after` dependencies exist before
        // the system set
        inline for (config.after) |s| {
            const parent_set_id = try self.getOrPutSystemSet(alloc, s);
            try self.graph.addDep(alloc, parent_set_id, .{ .set = self.graph.count });
        }

        _ = try self.putOneSystemSet(alloc, set);

        // TODO: config.before
    }

    /// Get a **system set** node that is the same with `set`,
    /// the new one will be put if not found.
    ///
    /// Return a node id.
    fn getOrPutSystemSet(
        self: *LabeledSchedule,
        alloc: std.mem.Allocator,
        comptime set: SystemSet,
    ) !Graph.Node.ID {
        for (self.graph.nodes()) |node| {
            if (node.id == .system) continue;
            const set_node = self.data.get(node.id.set).set;
            if (set_node.eql(set)) return node.id;
        }

        return self.putOneSystemSet(alloc, set);
    }

    /// Append a **system set** to the list and add a
    /// **system set** node to the graph.
    ///
    /// Return a node id
    fn putOneSystemSet(
        self: *LabeledSchedule,
        alloc: std.mem.Allocator,
        comptime set: SystemSet,
    ) !Graph.Node.ID {
        try self.data.append(alloc, .{ .set = set });
        return try self.graph.add(alloc, .set);
    }

    /// Get all node in the graph after sorting for scheduling.
    /// The caller owns the returned memory.
    ///
    /// See `Label.run()` to run a system by node id.
    pub fn schedule(
        self: LabeledSchedule,
        alloc: std.mem.Allocator,
    ) ![]const Graph.Node.ID {
        return self.graph.toposort(alloc);
    }

    /// Run a system by `node_id` in the graph.
    ///
    /// This function asserts that `node_id` contains the id of
    /// **a system** and `id` value is less than total number of systems
    /// in the schedule.
    pub fn run(
        self: LabeledSchedule,
        w: *World,
        node_id: Graph.Node.ID,
    ) !void {
        std.debug.assert(std.meta.activeTag(node_id) == .system);
        const system_node_id = node_id.system;
        std.debug.assert(system_node_id < self.data.len);

        try self
            .data
            .get(system_node_id)
            .system
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
    try test_label.addSystem(alloc, .fromFn(H.system1));
    try test_label.addSystem(alloc, .fromFn(H.system2));
    try test_label.addSystem(alloc, .fromFn(H.system3));

    const system_node_ids = try test_label.schedule(alloc);
    defer alloc.free(system_node_ids);

    for (system_node_ids, 0..) |id, i| {
        try std.testing.expectEqual(i, id.system);
        try test_label.run(&world, id);
    }

    // TODO: Added children
}

test "add systems with sets" {
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

    const SetA = SystemSet{ .name = "set_a" }; // node_id = 0
    const SetB = SystemSet{ .name = "set_b" }; // node_id = 1

    try test_label.addSetWithConfig(alloc, SetA, .{ .after = &.{SetB} });

    try test_label.addSystemWithConfig(alloc, .fromFn(H.system1), .{ .in_sets = &.{SetA} }); // node_id = 2
    try test_label.addSystemWithConfig(alloc, .fromFn(H.system2), .{ .in_sets = &.{SetB} }); // node_id = 3
    try test_label.addSystemWithConfig(alloc, .fromFn(H.system3), .{ .in_sets = &.{SetA} }); // node_id = 4

    const system_node_ids = try test_label.schedule(alloc);
    defer alloc.free(system_node_ids);

    const expected_ids = &[_]Graph.Node.ID{
        .{ .system = 3 },
        .{ .system = 2 },
        .{ .system = 4 },
    };

    for (system_node_ids) |id| {
        try test_label.run(&world, id);
    }

    for (system_node_ids, expected_ids) |id, i| {
        try std.testing.expectEqual(i, id);
        try test_label.run(&world, id);
    }
}
