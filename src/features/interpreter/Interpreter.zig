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
    /// Nothing action will be executed, the parser should return errors
    none,
    move: @import("../digger/mod.zig").action.MoveDirection,

    pub const Parser = struct {
        alloc: std.mem.Allocator,
        interpreter: *Interpreter,

        pub fn init(alloc: std.mem.Allocator, i: *Interpreter) Parser {
            return .{
                .alloc = alloc,
                .interpreter = i,
            };
        }

        pub fn parse(
            self: Parser,
            cmd_name: []const u8,
            arg_value: []const u8,
            node_tag: std.zig.Ast.Node.Tag,
        ) !Command {
            inline for (std.meta.fields(Command)) |f| {
                if (std.mem.eql(u8, f.name, cmd_name)) {
                    if (try self.parseArg(
                        f.name,
                        arg_value,
                        node_tag,
                    )) |arg| {
                        return @unionInit(Command, f.name, arg);
                    } else return .none;
                }
            }

            try self.interpreter.appendError(self.alloc, .{
                .tag = .unknown_action,
                .token = cmd_name,
            });
            return .none;
        }

        /// Initialized the arguments of a command based
        /// on `arg_value`.
        /// Return null if errors are exposed and messages
        /// will be written to `interpreter.errors`.
        ///
        /// This function assert the `node_tag` should
        /// correspond to the command's arg types.
        pub fn parseArg(
            self: Parser,
            comptime action: []const u8,
            arg_value: []const u8,
            node_tag: std.zig.Ast.Node.Tag,
        ) !?@FieldType(Command, action) {
            // TODO: handle more data types
            switch (@typeInfo(@FieldType(Command, action))) {
                .@"enum" => {
                    std.debug.assert(node_tag == .enum_literal);

                    const action_type = @FieldType(Command, action);
                    const normalized_action_type = try utils.normalizedActionType(
                        self.alloc,
                        @typeName(action_type),
                    );

                    return std.meta.stringToEnum(
                        action_type,
                        arg_value,
                    ) orelse {
                        try self.interpreter.appendError(self.alloc, .{
                            .tag = .expected_type_action,
                            .extra = .{
                                .expected_token = normalized_action_type,
                            },
                            .token = arg_value,
                        });
                        return null;
                    };
                },
                else => unreachable, // not supported type
            }
        }
    };
};

const Language = enum {
    zig,
    plaintext,
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

    if (actions.len > 0) {
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
