//! Interpreters implementation to parse the source code
//! from `ingame/terminal` into `Action`.
//!
//! All functions that have `alloc` as args dont need to free
//! because those are using `World.arena`, thats meaning all
//! allocations will be freed every frames.
//!
//! Supported languages:
//! * Plaintext
//! * Zig (WIP)
const std = @import("std");
const utils = @import("utils.zig");

pub const plaintext = @import("plaintext.zig");
pub const zig = @import("zig.zig");

const Interpreter = @This();

errors: std.ArrayList(Error) = .empty,

pub const Error = struct {
    tag: Tag,
    extra: union(enum) {
        none: void,
        expected_token: union(enum) {
            allocated_str: []const u8,
            str: []const u8,
        },
        from_languages: [][]const u8,
    } = .{ .none = {} },
    token: []const u8,

    pub const Tag = enum {
        /// Some languages need to define main functions
        /// like Zig, C, C++, Rust, and more. This error
        /// occurs when using those languages but players
        /// not define the `main` function.
        main_not_found,
        /// the errors are exposed from implemented languages.
        from_languages,
        unknown_action,
        expected_type_action,
        /// Errors in development
        not_supported_type,
    };

    pub fn deinit(self: *Error, alloc: std.mem.Allocator) void {
        switch (self.tag) {
            .expected_type_action => switch (self.extra.expected_token) {
                .allocated_str => |str| alloc.free(str),
                else => {},
            },
            .from_languages => {
                for (self.extra.from_languages) |err| {
                    alloc.free(err);
                }
                alloc.free(self.extra.from_languages);
            },
            else => {},
        }
    }

    pub fn expectTypeAction(
        alloc: std.mem.Allocator,
        interpreter: *Interpreter,
        expected_token: []const u8,
        found_token: []const u8,
        is_allocated: bool,
    ) !void {
        if (is_allocated) {
            interpreter.appendError(alloc, .{
                .tag = .expected_type_action,
                .extra = .{
                    .expected_token = .{
                        .allocated_str = expected_token,
                    },
                },
                .token = found_token,
            }) catch return Command.Parser.ParseError.OutOfMemory;
        } else {
            interpreter.appendError(alloc, .{
                .tag = .expected_type_action,
                .extra = .{
                    .expected_token = .{
                        .str = expected_token,
                    },
                },
                .token = found_token,
            }) catch return Command.Parser.ParseError.OutOfMemory;
        }
    }

    /// Write the `err` message to `writer`.
    ///
    /// TODO: display hints to fix error.
    pub fn render(err: Error, w: *std.Io.Writer) !void {
        try switch (err.tag) {
            .main_not_found => w.print("requires the `main` function to run.", .{}),
            .from_languages => {
                for (err.extra.from_languages) |msg| {
                    try w.print("{s}\n", .{msg});
                }
            },
            .unknown_action => w.print("function `{s}` unknown.", .{err.token}),
            .expected_type_action => switch (err.extra.expected_token) {
                inline else => |v| {
                    try w.print(
                        "expected `{s}` type, found `{s}`.",
                        .{ v, err.token },
                    );
                },
            },
            // TODO: remove this error
            .not_supported_type => w.print(
                "not supported type `{s}`, please contact with developers if you see this error.",
                .{err.token},
            ),
        };
    }
};

/// All *enum variant names* in the `Command` will be named according
/// to **the Zig function naming convention**. You can *convert* a implemented
/// language function name convention *into* enum variant names by *string
/// operations*.
pub const Command = union(enum) {
    @"if": IfStatementInfo,
    @"for": ForStatementInfo,
    end_for: void,
    // Commands in game
    move: @import("../digger/mod.zig").move.MoveDirection,
    isEdge: @import("../digger/mod.zig").check.EdgeDirection,

    pub const IfStatementInfo = struct {
        condition: CondExpr,
        /// number of commands in the `if` body
        num_of_cmds: u64,

        /// The condition expression
        pub const CondExpr = union(enum) {
            /// This field using for comparision operators
            /// (!=, >, < <=, >=, ==)
            number_literal: isize,
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

        pub fn deinit(self: *IfStatementInfo, alloc: std.mem.Allocator) void {
            self.condition.deinit(alloc);
        }

        pub fn default() IfStatementInfo {
            return .{
                .condition = undefined,
                .num_of_cmds = 0,
            };
        }
    };

    pub const ForStatementInfo = struct {
        condition: CondExpr,
        /// The index of the `for` statement in list
        start_idx: u64,

        pub const CondExpr = union(enum) {
            range: struct { start: usize, end: usize },
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
        /// arg_value = "down" & cmd = "move"
        /// ```
        ///
        /// * `arg_type` == `struct` => `arg_value` should be a `struct`.
        /// Example:
        /// ```
        /// arg_type = IfStatementInfo
        /// arg_value = IfStatementInfo {...} & cmd = "if"
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

                    const T = @FieldType(Command, cmd);

                    return std.meta.stringToEnum(
                        T,
                        cmd_value,
                    ) orelse {
                        const normalized_action_type = try utils.normalizedActionType(
                            alloc,
                            @typeName(T),
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
                    const StructType = @FieldType(Command, cmd);
                    if (@TypeOf(cmd_value) != StructType)
                        std.debug.panic("Expected `struct`, found `{s}`", .{
                            @typeName(@TypeOf(StructType)),
                        });
                    std.debug.assert(node_tag == .struct_init_dot or node_tag == .struct_init_dot_two);

                    return @as(StructType, cmd_value);
                },
                else => unreachable, // not supported type
            }
        }
    };
};

pub const Language = enum(i32) {
    plaintext = 0,
    zig = 1,
};

/// The caller should `free` the return value.
pub fn parse(
    self: *Interpreter,
    alloc: std.mem.Allocator,
    source: []const u8,
    lang: Language,
) ![]Command {
    const normalized_source = try utils.normalizedSource(alloc, source);
    defer alloc.free(normalized_source);

    const actions = try switch (lang) {
        .zig => zig.parse(alloc, self, normalized_source),
        .plaintext => plaintext.parse(alloc, self, normalized_source),
    };

    if (self.errors.items.len > 0) {
        var aw = std.Io.Writer.Allocating.init(alloc);
        defer aw.deinit();
        const errs = try self.errors.toOwnedSlice(alloc);
        defer {
            alloc.free(errs);
            self.errors.deinit(alloc);
        }

        for (errs) |*err| {
            try err.render(&aw.writer);
            defer err.deinit(alloc);

            const msg = try aw.toOwnedSlice();
            defer alloc.free(msg);
            std.log.debug("{s}", .{msg});
        }
    }

    return actions;
}

pub fn appendError(self: *Interpreter, alloc: std.mem.Allocator, err: Error) !void {
    try self.errors.append(alloc, err);
}
