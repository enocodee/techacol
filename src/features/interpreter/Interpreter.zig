//! Interpreters implementation to parse the source code
//! from `ingame/terminal` into `Command`.
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

const Command = @import("command.zig").Command;
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
        defer self.errors.deinit(alloc);

        for (self.errors.items) |*err| {
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
