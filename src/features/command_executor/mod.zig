const std = @import("std");
const World = @import("ecs").World;
const QueryError = World.QueryError;
const Command = @import("../interpreter/command.zig").Command;

const digger = @import("../digger/mod.zig");

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
    /// `null` if there aren't any loops running.
    loop_state: ?struct {
        start_idx: usize,
        curr_iter_time: usize = 1,
        total_iter: usize,
    } = null,
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

    pub fn clearQueue(self: *CommandExecutor, alloc: std.mem.Allocator) void {
        for (self.queue.items) |*it| {
            if (std.meta.activeTag(it.*) == .@"if") {
                it.@"if".deinit(alloc);
            }
        }
        self.curr_idx = 0;
        self.count = 0;
        self.queue.clearAndFree(alloc);
    }

    pub fn enqueue(self: *CommandExecutor, cmd: Command) !void {
        self.is_running = true;
        self.timer = try .start();
        try self.queue.append(self.alloc, cmd);
        self.count += 1;
    }

    /// return the next node and increase the current idx in queue
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
                    try self.handleNode(w, command);
                } else {
                    self.timer = null;
                    self.is_running = false;
                    self.clearQueue(w.alloc);
                }
            }
        }
    }

    fn handleNode(
        self: *CommandExecutor,
        w: *World,
        command: Command,
    ) QueryError!void {
        switch (command) {
            .move => |direction| {
                self.timer.?.reset();
                try digger.move.control(w, direction);
            },
            .isEdge => |direction| {
                self.timer.?.reset();
                self.last_bool_result = try digger.check.isEdge(
                    w,
                    direction,
                );
            },
            // NOTE: Language features
            .skip => |value| self.curr_idx += value + 1,
            .@"if" => |info| {
                const cond_expr_result = try self.*.evaluateCondExpr(
                    w,
                    @constCast(&info.condition),
                );

                if (!cond_expr_result.bool)
                    self.curr_idx += info.then_num_cmds;
            },
            .@"while" => |info| {
                const cond_expr_result = try self.*.evaluateCondExpr(
                    w,
                    @constCast(&info.condition),
                );

                if (cond_expr_result.bool) {
                    if (self.loop_state) |*state| {
                        state.total_iter += 1;
                    } else {
                        self.loop_state = .{
                            // back to the `while` statement to re-evaluate the condition
                            .start_idx = info.start_idx,
                            .total_iter = 1,
                        };
                    }
                }
            },
            .@"for" => |info| {
                const start_stmt_idx = self.curr_idx + info.start_idx;

                switch (info.condition) {
                    .range => |r| {
                        const times = r.end - r.start;
                        self.loop_state = .{
                            .start_idx = start_stmt_idx,
                            .total_iter = times,
                        };
                    },
                }
            },
            .end_loop => {
                if (self.loop_state.?.curr_iter_time > self.loop_state.?.total_iter) {
                    self.loop_state = null;
                    return;
                }
                self.*.loop_state.?.curr_iter_time += 1;
                self.curr_idx = self.*.loop_state.?.start_idx;
            },
        }
    }

    const CondValue = union(enum) {
        bool: bool,
        int: usize,
    };

    /// return the final result of the condition expression of the `if` command
    fn evaluateCondExpr(
        self: *CommandExecutor,
        w: *World,
        condition: *Command.CondExpr,
    ) QueryError!CondValue {
        switch (condition.*) {
            .literal => |v| return .{ .bool = v },
            .number_literal => |v| return .{ .int = v },
            .expr => {
                const expr_cmd = self.next().?;
                try self.handleNode(w, expr_cmd);
                return .{ .bool = self.last_bool_result.? };
            },
            .expr_and => |expr| {
                const values = try self.evaluateCondExpr2(w, expr);
                return .{ .bool = values.@"0".bool and values.@"1".bool };
            },
            .expr_or => |expr| {
                const values = try self.evaluateCondExpr2(w, expr);
                return .{ .bool = values.@"0".bool or values.@"1".bool };
            },
            .not_expr => |expr| {
                const lhs = expr[0];
                const lhs_value = try self.evaluateCondExpr(w, lhs);

                return .{ .bool = lhs_value.bool };
            },
            .greater => |expr| {
                const values = try self.evaluateCondExpr2(w, expr);
                return .{ .bool = values.@"0".int > values.@"1".int };
            },
            .greater_or_equal => |expr| {
                const values = try self.evaluateCondExpr2(w, expr);
                return .{ .bool = values.@"0".int >= values.@"1".int };
            },
            .less => |expr| {
                const values = try self.evaluateCondExpr2(w, expr);
                return .{ .bool = values.@"0".int < values.@"1".int };
            },
            .less_or_equal => |expr| {
                const values = try self.evaluateCondExpr2(w, expr);
                return .{ .bool = values.@"0".int <= values.@"1".int };
            },
            .equal => |expr| {
                const values = try self.evaluateCondExpr2(w, expr);
                return .{ .bool = values.@"0".int == values.@"1".int };
            },
            .diff => |expr| {
                const values = try self.evaluateCondExpr2(w, expr);
                return .{ .bool = values.@"0".int != values.@"1".int };
            },
        }
    }

    /// Evaluate two-handside condition expressions
    pub fn evaluateCondExpr2(
        self: *CommandExecutor,
        w: *World,
        expr: struct {
            *Command.CondExpr,
            *Command.CondExpr,
        },
    ) QueryError!struct { CondValue, CondValue } {
        const lhs = expr[0];
        const lhs_value = try self.evaluateCondExpr(w, lhs);

        const rhs = expr[1];
        const rhs_value = try self.evaluateCondExpr(w, rhs);

        return .{ .@"0" = lhs_value, .@"1" = rhs_value };
    }
};
