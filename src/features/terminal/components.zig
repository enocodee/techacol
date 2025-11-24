const std = @import("std");

const digger = @import("../digger/mod.zig");

const World = @import("ecs").World;
const Interpreter = @import("../interpreter/Interpreter.zig");
const Command = Interpreter.Command;

pub const Terminal = struct {};

/// All commands will be executed in FIFO order
pub const CommandExecutor = struct {
    queue: Queue,
    alloc: std.mem.Allocator,
    /// The timestamp of the previous command execution
    /// in miliseconds.
    /// The timer is started from the first commmands is added.
    timer: ?std.time.Timer = null,
    _arena: *std.heap.ArenaAllocator,
    is_running: bool = false,

    const Queue = std.SinglyLinkedList;
    const Item = struct {
        data: Command,
        node: Queue.Node = .{},
    };

    pub fn init(alloc: std.mem.Allocator) !CommandExecutor {
        const arena = try alloc.create(std.heap.ArenaAllocator);
        arena.* = .init(alloc);

        return .{
            .queue = .{},
            .alloc = arena.allocator(),
            ._arena = arena,
        };
    }

    pub fn deinit(self: *CommandExecutor, _: std.mem.Allocator) void {
        const alloc = self._arena.child_allocator;
        self._arena.deinit();
        alloc.destroy(self._arena);
    }

    pub fn enqueue(self: *CommandExecutor, cmd: Command) !void {
        const it = try self.alloc.create(Item);
        it.* = .{ .data = cmd };

        if (self.queue.first == null) {
            self.timer = try .start();
            self.queue.first = &it.node;
        } else {
            var curr_node = self.queue.first.?;
            while (curr_node.next != null) {
                curr_node = curr_node.next.?;
            }

            curr_node.insertAfter(&it.node);
        }
    }

    pub fn dequeue(self: *CommandExecutor) ?Command {
        const first_node = self.queue.popFirst() orelse return null;
        const item: *Item = @fieldParentPtr("node", first_node);
        const data = item.data;
        self.alloc.destroy(item);
        return data;
    }

    /// Execute next command in the queue in a duration
    pub fn execNext(
        self: *CommandExecutor,
        w: *World,
        /// (miliseconds)
        duration: u64,
    ) !void {
        if (self.timer) |*timer| {
            const target_ns = duration * std.time.ns_per_ms;
            const lap = timer.read();

            if (lap > target_ns) {
                if (self.dequeue()) |command| {
                    self.is_running = true;
                    timer.reset();

                    try switch (command) {
                        .move => |direction| digger.action.control(w, direction),
                    };
                } else {
                    self.timer = null;
                    self.is_running = false;
                }
            }
        }
    }
};
