const std = @import("std");

const digger = @import("../digger/mod.zig");

const World = @import("ecs").World;
const Interpreter = @import("../interpreter/Interpreter.zig");
const Command = Interpreter.Command;

pub const Terminal = struct {};

/// All commands will be executed in FIFO order
pub const CommandExecutor = struct {
    queue: Queue,
    /// the `World.alloc`
    alloc: std.mem.Allocator,
    // The boolean result of condition expressions of `if` statements.
    // This field should be used when the if condition type is `expr` and
    // evaluated after executing `if` commands.
    //
    // This field is also the result of the before expression condition, its useful
    // to calculate if the number of expressions greater than 1.
    //
    // `null` if this is used in the first time.
    last_bool_result: ?bool = null,
    /// The timestamp of the previous command execution
    /// in miliseconds.
    /// The timer is started from the first commmands is added.
    timer: ?std.time.Timer = null,
    is_running: bool = false,
    /// The number of available commands in queue.
    count: u64 = 0,
    /// The current index to get node.
    curr_idx: u64 = 0,

    const Queue = std.ArrayList(Command);

    pub fn init(alloc: std.mem.Allocator) CommandExecutor {
        return .{
            .queue = .empty,
            .alloc = alloc,
        };
    }

    /// Drain nodes in the queue.
    pub fn deinit(self: *CommandExecutor, _: std.mem.Allocator) void {
        self.queue.deinit(self.alloc);
    }

    pub fn enqueue(self: *CommandExecutor, cmd: Command) !void {
        self.is_running = true;
        self.timer = try .start();
        try self.queue.append(self.alloc, cmd);
        self.count += 1;
    }

    /// return the next node in the queue.
    pub fn next(self: *CommandExecutor) ?Command {
        const idx = self.curr_idx;
        if (idx >= self.count) return null;

        const it = self.queue.items[idx];
        self.curr_idx += 1;
        return it;
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
                if (self.next()) |command| {
                    timer.reset();

                    try self.handleNode(w, command);
                } else {
                    self.timer = null;
                    self.is_running = false;
                }
            }
        }
    }

    fn handleNode(
        self: *CommandExecutor,
        w: *World,
        command: Command,
    ) @import("ecs").World.QueryError!void {
        switch (command) {
            .move => |direction| try digger.move.control(w, direction),
            .isEdge => |direction| self.last_bool_result = try digger.check.isEdge(
                w,
                direction,
            ),
            .@"if" => |info| {
                const cond_expr_result = try self.*.evaluateCondExpr(
                    w,
                    @constCast(&info.condition),
                    info.num_of_cmds,
                );

                if (!cond_expr_result) {
                    var idx: usize = 1;
                    var curr_node = self.next();
                    while (curr_node != null and idx < info.num_of_cmds) {
                        curr_node = self.next();
                        idx += 1;
                    }
                }
            },
        }
    }

    /// return the final result of the condition expression of the `if` command
    fn evaluateCondExpr(
        self: *CommandExecutor,
        w: *World,
        condition: *Interpreter.Command.IfStatementInfo.CondExpr,
        /// Number of cmds in the `if` body
        num_of_cmds: u64,
    ) !bool {
        defer condition.deinit(self.alloc);

        switch (condition.*) {
            .value => |v| return v,
            .expr => {
                const expr_cmd = self.next().?;
                try self.handleNode(w, expr_cmd);
                return self.last_bool_result.?;
            },
            .expr_and => |expr| {
                const lhs = expr[1];
                const lhs_value = try self.evaluateCondExpr(w, lhs, num_of_cmds);

                const rhs = expr[0];
                const rhs_value = try self.evaluateCondExpr(w, rhs, num_of_cmds);

                return (lhs_value and rhs_value);
            },
            .expr_or => |expr| {
                const lhs = expr[1];
                const lhs_value = try self.evaluateCondExpr(w, lhs, num_of_cmds);

                const rhs = expr[0];
                const rhs_value = try self.evaluateCondExpr(w, rhs, num_of_cmds);

                return (lhs_value or rhs_value);
            },
            .not_expr => |expr| {
                const lhs = expr[0];
                const lhs_value = try self.evaluateCondExpr(w, lhs, num_of_cmds);

                return !lhs_value;
            },
        }
    }
};
