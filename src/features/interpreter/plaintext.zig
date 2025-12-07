// TODO: should i create an AST Parser and make this
// as a new scripting language (just use ingame)?
const std = @import("std");

const Interpreter = @import("Interpreter.zig");
const Command = @import("command.zig").Command;

const Error = Interpreter.Error;

pub fn parse(
    alloc: std.mem.Allocator,
    interpreter: *Interpreter,
    source: []const u8,
) ![]Command {
    const command_parser: Command.Parser = .init(interpreter);
    var commands: std.ArrayList(Command) = .empty;
    var line_iter = std.mem.splitSequence(u8, source, "\r\n");

    while (line_iter.next()) |line| {
        var tokenizer = std.mem.tokenizeAny(u8, line, " ");

        const fn_name: []const u8 = tokenizer.next() orelse break;
        const should_be_value = tokenizer.next() orelse {
            try interpreter.appendError(alloc, .{
                .tag = .expected_type_action,
                .extra = .{ .expected_token = .{ .str = "arguments" } },
                .token = "empty",
            });
            break;
        };

        var maybe_cmd: ?Command = null;
        if (std.mem.eql(u8, fn_name, "if")) {
            // TODO: remove this
            maybe_cmd = try command_parser.parse(
                alloc,
                "if",
                Command.info.If{
                    .condition = .{ .literal = false },
                    .then_num_cmds = 0,
                    .else_num_cmds = 0,
                },
                .enum_literal,
            );
        } else {
            maybe_cmd = try command_parser.parse(
                alloc,
                fn_name,
                should_be_value,
                .enum_literal,
            );
        }

        if (maybe_cmd) |cmd| {
            try commands.append(alloc, cmd);
        }
    }
    return commands.toOwnedSlice(alloc);
}

test "parse action (plaintext)" {
    // simulate the `World.arena`
    var base_alloc = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer base_alloc.deinit();
    const alloc = base_alloc.allocator();

    var interpreter: Interpreter = .{};
    const list_err = &interpreter.errors;

    const action_1 = "move up";
    const parsed_1 = try parse(alloc, &interpreter, action_1);
    const result_1: Command = .{
        .move = .up,
    };
    try std.testing.expectEqual(1, parsed_1.len);
    try std.testing.expectEqual(result_1, parsed_1[0]);

    const action_2 = "nothing arg";
    _ = try parse(alloc, &interpreter, action_2);

    var err_2 = list_err.*.getLast();
    defer err_2.deinit(alloc);

    try std.testing.expectEqualDeep(Error{
        .tag = .unknown_action,
        .token = "nothing",
    }, err_2);

    const action_3 = "move forward";
    _ = try parse(alloc, &interpreter, action_3);

    var err_3 = list_err.*.getLast();
    defer err_3.deinit(alloc);

    try std.testing.expectEqualDeep(Error{
        .tag = .expected_type_action,
        .extra = .{ .expected_token = .{ .allocated_str = "digger.MoveDirection" } },
        .token = "forward",
    }, err_3);
}
