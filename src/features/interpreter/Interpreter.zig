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
        expected_token: []const u8,
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
            .expected_type_action => w.print(
                "expected `{s}` type, found `{s}`.",
                .{ err.extra.expected_token, err.token },
            ),
            // TODO: remove this error
            .not_supported_type => w.print(
                "not supported type `{s}`, please contact with developers if you see this error.",
                .{err.token},
            ),
        };
    }
};

pub const Command = union(enum) {
    @"if": IfStatementInfo,
    move: @import("../digger/mod.zig").move.MoveDirection,

    pub const IfStatementInfo = struct {
        condition_value: bool,
        /// number of commands in the `if` body
        num_of_cmds: u64,
    };

    pub const Parser = struct {
        interpreter: *Interpreter,

        pub const Error = error{OutOfMemory};

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
        ) Parser.Error!?Command {
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
        ) Parser.Error!?@FieldType(Command, cmd) {
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
                    std.debug.assert(node_tag == .enum_literal);

                    const T = @FieldType(Command, cmd);
                    const normalized_action_type = utils.normalizedActionType(
                        alloc,
                        @typeName(T),
                    ) catch return Parser.Error.OutOfMemory;

                    return std.meta.stringToEnum(
                        T,
                        cmd_value,
                    ) orelse {
                        self.interpreter.appendError(alloc, .{
                            .tag = .expected_type_action,
                            .extra = .{
                                .expected_token = normalized_action_type,
                            },
                            .token = cmd_value,
                        }) catch return Parser.Error.OutOfMemory;
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

pub fn parse(
    self: *Interpreter,
    alloc: std.mem.Allocator,
    source: []const u8,
    lang: Language,
) ![]Command {
    const normalized_source = try utils.normalizedSource(alloc, source);

    const actions = try switch (lang) {
        .zig => zig.parse(alloc, self, normalized_source),
        .plaintext => plaintext.parse(alloc, self, normalized_source),
    };

    if (actions.len <= 0) {
        var aw = std.Io.Writer.Allocating.init(alloc);
        const errs = try self.errors.toOwnedSlice(alloc);
        for (errs) |err| {
            try err.render(&aw.writer);
            std.log.debug("{s}", .{try aw.toOwnedSlice()});
        }
    }

    return actions;
}

pub fn appendError(self: *Interpreter, alloc: std.mem.Allocator, err: Error) !void {
    try self.errors.append(alloc, err);
}
