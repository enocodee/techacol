//! All *enum variant names* in the `Command` will be named according
//! to **the Zig function naming convention**. You can *convert* a implemented
//! language function name convention *into* enum variant names by *string
//! operations*.

const std = @import("std");
const utils = @import("utils.zig");

const Interpreter = @import("Interpreter.zig");
const Error = @import("Interpreter.zig").Error;

pub const Command = union(enum) {
    // --- Language features ---
    /// If statements
    @"if": info.If,
    /// While statements
    @"while": info.While,
    /// For statements
    @"for": info.For,
    /// Skip number of commands in queue
    skip: u64,
    end_loop: void,

    // --- Commands in game ---
    /// Move the digger in the specified direction.
    move: @import("../digger/mod.zig").move.MoveDirection,
    /// Check if the specified direction is an edge.
    isEdge: @import("../digger/mod.zig").check.EdgeDirection,

    /// The condition expressions
    pub const CondExpr = union(enum) {
        /// This field using for comparision operators
        /// (!=, >, < <=, >=, ==)
        number_literal: usize,
        /// if(true) {...}
        /// if(false) {...}
        ///
        /// Using boolean values literally.
        literal: bool,
        /// if (callA()) {...}
        ///
        /// Use **an expression** to evaluate the condition value.
        ///
        /// If this type is enabled, the expression should be
        /// append after the `if` command.
        expr,
        /// (lhs and rhs)
        ///
        /// lhs, rhs: an expression or boolean value
        ///
        /// If this type is enabled, expressions should be
        /// append after the `if` command.
        expr_and: struct { *CondExpr, *CondExpr },
        /// (lhs or rhs)
        ///
        /// lhs, rhs: an expression or boolean value
        ///
        /// If this type is enabled, expressions should be
        /// append after the `if` command.
        expr_or: struct { *CondExpr, *CondExpr },
        /// !lhs
        ///
        /// lhs: an expression or boolean value
        ///
        /// If this type is enabled, expressions should be
        /// append after the `if` command.
        not_expr: struct { *CondExpr },
        /// lhs > rhs
        ///
        /// lhs, rhs: an expression or number value
        ///
        /// If this type is enabled, expressions should be
        /// append after the `if` command.
        greater: struct { *CondExpr, *CondExpr },
        /// lhs >= rhs
        ///
        /// lhs: an expression or number value
        ///
        /// If this type is enabled, expressions should be
        /// append after the `if` command.
        greater_or_equal: struct { *CondExpr, *CondExpr },
        /// lhs < rhs
        ///
        /// lhs, rhs: an expression or number literal
        ///
        /// If this type is enabled, expressions should be
        /// append after the `if` command.
        less: struct { *CondExpr, *CondExpr },
        /// lhs <= rhs
        ///
        /// lhs, rhs: an expression or number literal
        ///
        /// If this type is enabled, expressions should be
        /// append after the `if` command.
        less_or_equal: struct { *CondExpr, *CondExpr },
        /// lhs == rhs
        ///
        /// lhs, rhs: an expression or number literal
        ///
        /// If this type is enabled, expressions should be
        /// append after the `if` command.
        equal: struct { *CondExpr, *CondExpr },
        /// lhs != rhs
        ///
        /// lhs, rhs: an expression or number literal
        ///
        /// If this type is enabled, expressions should be
        /// append after the `if` command.
        diff: struct { *CondExpr, *CondExpr },

        pub fn deinit(self: *CondExpr, alloc: std.mem.Allocator) void {
            switch (self.*) {
                .expr_and,
                .expr_or,

                .greater,
                .greater_or_equal,
                .less,
                .less_or_equal,
                .equal,
                .diff,
                => |v| {
                    v.@"0".deinit(alloc);
                    v.@"1".deinit(alloc);
                    alloc.destroy(v[0]);
                    alloc.destroy(v[1]);
                },

                .not_expr => |v| {
                    v.@"0".deinit(alloc);
                    alloc.destroy(v[0]);
                },

                else => {},
            }
        }
    };

    pub const info = struct {
        pub const If = struct {
            condition: CondExpr,
            /// Number of commands in the `if` body
            then_num_cmds: u64,
            /// Number of commands in the `else`, `else_if` body
            else_num_cmds: u64,

            pub fn deinit(self: *If, alloc: std.mem.Allocator) void {
                self.condition.deinit(alloc);
            }

            pub fn default() If {
                return .{
                    .condition = undefined,
                    .then_num_cmds = 0,
                    .else_num_cmds = 0,
                };
            }
        };

        pub const While = struct {
            /// Boolean conditions
            condition: CondExpr,
            /// number of commands in the `while` body
            start_idx: u64,
        };

        pub const For = struct {
            /// Slices
            condition: @This().CondExpr,
            /// The index of the `for` statement in list
            start_idx: u64,

            pub const CondExpr = union(enum) {
                range: struct { start: usize, end: usize },
            };
        };
    };

    pub const Parser = struct {
        interpreter: *Interpreter,

        pub const ParseError = std.mem.Allocator.Error || std.fmt.ParseIntError;

        pub fn init(i: *Interpreter) Parser {
            return .{
                .interpreter = i,
            };
        }

        pub fn parse(
            self: Parser,
            alloc: std.mem.Allocator,
            cmd_name: []const u8,
            cmd_value: anytype,
            node_tag: std.zig.Ast.Node.Tag,
        ) ParseError!?Command {
            inline for (std.meta.fields(Command)) |f| {
                if (std.mem.eql(u8, f.name, cmd_name)) {
                    if (try self.parseArg(
                        alloc,
                        f.name,
                        cmd_value,
                        node_tag,
                    )) |arg| {
                        return @unionInit(Command, f.name, arg);
                    } else return null;
                }
            }

            try self.interpreter.appendError(alloc, .{
                .tag = .unknown_action,
                .token = cmd_name,
            });
            return null;
        }

        /// Initialized the arguments of a command based
        /// on `arg_value`.
        /// Return null if errors are exposed and messages
        /// will be written to `interpreter.errors`.
        ///
        /// This function assert the `node_tag` should
        /// correspond to the command's arg types.
        ///
        /// # Features:
        /// * `arg_type` == `enum` => `arg_value` should be a `[]const u8` (enum variant).
        /// Example:
        /// ```
        /// arg_type = digger.MoveDirection.down
        /// cmd_value = "down" & cmd = "move"
        /// ```
        ///
        /// * `arg_type` == `struct` => `arg_value` should be a `struct`.
        /// Example:
        /// ```
        /// arg_type = IfStatementInfo
        /// cmd_value = IfStatementInfo {...} & cmd = "if"
        /// ```
        pub fn parseArg(
            self: Parser,
            alloc: std.mem.Allocator,
            comptime cmd: []const u8,
            cmd_value: anytype,
            node_tag: std.zig.Ast.Node.Tag,
        ) ParseError!?@FieldType(Command, cmd) {
            const typeInfo = @typeInfo(@FieldType(Command, cmd));
            // TODO: handle more data types:
            //       + Struct
            //       + Array
            const ReturnType = @FieldType(Command, cmd);

            switch (typeInfo) {
                .@"enum" => {
                    if (@TypeOf(cmd_value) != []const u8)
                        std.debug.panic("Expected `[]const u8`, found `{s}`.", .{
                            @typeName(@TypeOf(cmd_value)),
                        });
                    if (node_tag != .enum_literal)
                        try Error.expectTypeAction(
                            alloc,
                            self.interpreter,
                            "enum_literal",
                            @tagName(node_tag),
                            false,
                        );

                    return std.meta.stringToEnum(
                        ReturnType,
                        cmd_value,
                    ) orelse {
                        const normalized_action_type = try utils.normalizedActionType(
                            alloc,
                            @typeName(ReturnType),
                        );
                        errdefer alloc.free(normalized_action_type);
                        try Error.expectTypeAction(
                            alloc,
                            self.interpreter,
                            normalized_action_type,
                            cmd_value,
                            true,
                        );
                        return null;
                    };
                },
                .@"struct" => {
                    if (@TypeOf(cmd_value) != ReturnType)
                        std.debug.panic("Expected `struct`, found `{s}`", .{
                            @typeName(@TypeOf(ReturnType)),
                        });
                    std.debug.assert(node_tag == .struct_init_dot or node_tag == .struct_init_dot_two);

                    return @as(ReturnType, cmd_value);
                },
                .int => {
                    if (@TypeOf(cmd_value) != ReturnType)
                        std.debug.panic("Expected `{s}`, found `{s}`", .{
                            @typeName(ReturnType),
                            @typeName(@TypeOf(ReturnType)),
                        });
                    @as(ReturnType, @intCast(cmd_value));
                },
                else => unreachable, // not supported type
            }
        }
    };
};
