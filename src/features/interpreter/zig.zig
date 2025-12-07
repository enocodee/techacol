const std = @import("std");

const Interpreter = @import("Interpreter.zig");

const Command = @import("command.zig").Command;
const CondExpr = Command.CondExpr;
const ParseError = Command.Parser.ParseError;
const Ast = std.zig.Ast;

pub fn parse(
    alloc: std.mem.Allocator,
    interpreter: *Interpreter,
    source: [:0]const u8,
) ![]Command {
    var commands: std.ArrayList(Command) = .empty;
    defer commands.deinit(alloc);

    var command_parser: Command.Parser = .init(interpreter);
    var ast = try Ast.parse(alloc, source, .zig);
    defer ast.deinit(alloc);
    try extractErrorFromAst(alloc, interpreter, ast);

    if (interpreter.errors.items.len > 0) return &.{};

    return parseMainNode(
        alloc,
        &command_parser,
        ast,
    );
}

/// Get the first `main` function node index from AST
fn getMainNodeIdx(ast: Ast) ?Ast.Node.Index {
    const root = ast.rootDecls();
    var main_node_idx: ?std.zig.Ast.Node.Index = null;

    if (root.len == 1) {
        if (isMain(ast, root[0]))
            main_node_idx = root[0];
    } else {
        for (root) |i| {
            if (isMain(ast, i)) main_node_idx = i;
        }
    }
    return main_node_idx;
}

pub fn isMain(ast: Ast, index: Ast.Node.Index) bool {
    const node_tag = ast.nodeTag(index);
    // ignore if the node is not `fn_decl`
    if (node_tag != .fn_decl) return false;

    var fn_proto_buf: [1]std.zig.Ast.Node.Index = undefined;
    const fn_proto = ast.fullFnProto(&fn_proto_buf, index).?;

    if (fn_proto.name_token) |token_fn_name_idx| {
        const fn_name = ast.tokenSlice(token_fn_name_idx);
        if (std.mem.eql(u8, "main", fn_name)) return true;
    }
    return false;
}

/// Return `null` if the main node not found.
fn parseMainNode(
    alloc: std.mem.Allocator,
    command_parser: *Command.Parser,
    ast: Ast,
) ![]Command {
    var cmds: std.ArrayList(Command) = .empty;
    defer cmds.deinit(alloc);
    // TODO: enable user to declare custom functions, variables, ..., like normal.
    // NOTE: currently, players can only declare the `main` function
    //       and use available functions ingame.

    // get main node (`fn main()`)
    const main_node_idx = getMainNodeIdx(ast) orelse {
        try command_parser.interpreter.appendError(alloc, .{
            .tag = .main_not_found,
            .token = "",
        });
        return &.{};
    };

    const block_node_idx = ast.nodeData(main_node_idx).node_and_node[1];
    // get nodes in main body
    var body_node_buf: [2]Ast.Node.Index = undefined;
    const body_node_idxs = ast.blockStatements(&body_node_buf, block_node_idx).?;

    for (body_node_idxs) |idx| {
        try parseNode(
            alloc,
            command_parser,
            ast,
            idx,
            &cmds,
        );
    }

    return cmds.toOwnedSlice(alloc);
}

/// Parse AST node by node index and write
/// commands (can be **one** or **many**) to `list`
fn parseNode(
    alloc: std.mem.Allocator,
    command_parser: *Command.Parser,
    ast: Ast,
    idx: Ast.Node.Index,
    list: *std.ArrayList(Command),
) ParseError!void {
    const node_tag = ast.nodeTag(idx);

    switch (node_tag) {
        .call_one => try parseCallNode(alloc, command_parser, ast, idx, list),
        .if_simple,
        .@"if",
        => try parseIfNode(alloc, command_parser, ast, idx, list),
        .for_simple => try parseForNode(alloc, command_parser, ast, idx, list),
        .while_simple => try parseWhileNode(alloc, command_parser, ast, idx, list),
        else => unreachable, // unsupported node tag
    }
}

/// Parse a call node and write a command to the `list`.
fn parseCallNode(
    alloc: std.mem.Allocator,
    command_parser: *Command.Parser,
    ast: Ast,
    idx: Ast.Node.Index,
    list: *std.ArrayList(Command),
) ParseError!void {
    var call_buf: [1]Ast.Node.Index = undefined;
    const call = ast.fullCall(&call_buf, idx).?;

    // Extract the call node
    const fn_name_tok_i = ast.nodes.get(@intFromEnum(call.ast.fn_expr)).main_token;
    const fn_name = ast.tokenSlice(fn_name_tok_i);

    // NOTE: we know that just one param in the function now.
    //       EX: `move(.up)`, `move(.down)`
    const arg_idx = call.ast.params[0];
    const arg_node_tag = ast.nodeTag(arg_idx);

    const arg_tok_i = ast.nodes.get(@intFromEnum(arg_idx)).main_token;
    const arg_value = ast.tokenSlice(arg_tok_i);

    const optional = try command_parser.parse(alloc, fn_name, arg_value, arg_node_tag);

    if (optional) |cmd| {
        try list.append(alloc, cmd);
    }
}

/// Parse all nodes of the `if` body and write all to
/// the `list`.
/// Return number of written nodes.
fn parseIfNode(
    alloc: std.mem.Allocator,
    command_parser: *Command.Parser,
    ast: Ast,
    idx: Ast.Node.Index,
    list: *std.ArrayList(Command),
) ParseError!void {
    const if_statement = ast.fullIf(idx).?;
    const cond_expr_idx = if_statement.ast.cond_expr;
    const if_cmd_idx = list.items.len;

    { // add the `if` command
        try list.append(alloc, .{
            .@"if" = .default(),
        });

        const if_cond = try parseCondExpr(alloc, command_parser, ast, cond_expr_idx, list);
        list.items[if_cmd_idx].@"if".condition = if_cond;
    }

    { // parse and get nodes in the if body
        const if_body_nodes = get_body_nodes: {
            const semi_node_idx = if_statement.ast.then_expr;
            var if_body_buf: [2]Ast.Node.Index = undefined;
            break :get_body_nodes ast.blockStatements(&if_body_buf, semi_node_idx).?;
        };
        const count1 = list.items.len;

        for (if_body_nodes) |i| {
            try parseNode(alloc, command_parser, ast, i, list);
        }
        const count2 = list.items.len - count1;
        if (count2 > 0) {
            // plus one for the `jump` command
            list.items[if_cmd_idx].@"if".then_num_cmds = count2 + 1;
        }
    }

    { // parse `else` or `else if` statement
        // We can easily to guess this count is idx of the `skip` command,
        // since idx = count - 1, and we add the `skip` cmd after this line.
        const count1 = list.items.len;
        // add a jump command after the last command in `if` body
        try list.append(alloc, .{
            .skip = 0,
        });

        if (if_statement.ast.else_expr.unwrap()) |else_i| {
            const node_tag = ast.nodeTag(else_i);

            switch (node_tag) {
                // else
                .block_two_semicolon => try parseBlockNode(alloc, command_parser, ast, else_i, list),
                // else if
                .if_simple, .@"if" => try parseIfNode(alloc, command_parser, ast, else_i, list),
                else => unreachable,
            }
            // Re-assign amount of commands to skip
        }

        const count2 = list.items.len - (count1 + 1);
        if (count2 > 0) {
            list.*.items[count1 - 1].skip = count2;
        }
    }
}

/// Parse all nodes of the `if` body and write all to
/// the `list`. Then, return num of written nodes.
fn parseBlockNode(
    alloc: std.mem.Allocator,
    command_parser: *Command.Parser,
    ast: Ast,
    idx: Ast.Node.Index,
    list: *std.ArrayList(Command),
) ParseError!void {
    var else_body_buf: [2]Ast.Node.Index = undefined;
    const else_body__nodes = ast.blockStatements(&else_body_buf, idx).?;

    for (else_body__nodes) |i| {
        try parseNode(alloc, command_parser, ast, i, list);
    }
}

fn parseWhileNode(
    alloc: std.mem.Allocator,
    command_parser: *Command.Parser,
    ast: Ast,
    idx: Ast.Node.Index,
    list: *std.ArrayList(Command),
) ParseError!void {
    const while_statement = ast.whileSimple(idx);
    const cond_expr_idx = while_statement.ast.cond_expr;
    const items_count = list.items.len;

    try list.append(alloc, .{
        .@"while" = .{
            .start_idx = items_count,
            .condition = undefined,
        },
    });

    const while_cond = try parseCondExpr(alloc, command_parser, ast, cond_expr_idx, list);
    list.items[items_count].@"while".condition = while_cond;

    const semi_node_idx = while_statement.ast.then_expr;
    var while_body_buf: [2]Ast.Node.Index = undefined;
    const while_body_nodes = ast.blockStatements(&while_body_buf, semi_node_idx).?;

    for (while_body_nodes) |i| {
        _ = try parseNode(alloc, command_parser, ast, i, list);
    }

    try list.append(alloc, .{ .end_loop = {} });
}

/// Parse condition expressions in `if`, `while` statements
pub fn parseCondExpr(
    alloc: std.mem.Allocator,
    command_parser: *Command.Parser,
    ast: Ast,
    idx: Ast.Node.Index,
    list: *std.ArrayList(Command),
) ParseError!CondExpr {
    const node_tag = ast.nodeTag(idx);
    var cond: CondExpr = undefined;

    switch (node_tag) {
        .identifier => {
            const main_token = ast.nodeMainToken(idx);
            cond = .{ .literal = std.mem.eql(
                u8,
                ast.tokenSlice(main_token),
                "true",
            ) };
        },
        .number_literal => {
            const main_token = ast.nodeMainToken(idx);
            cond = .{ .number_literal = try std.fmt.parseInt(
                usize,
                ast.tokenSlice(main_token),
                10,
            ) };
        },
        .call_one => {
            try parseCallNode(alloc, command_parser, ast, idx, list);
            cond = .{ .expr = {} };
        },
        .bool_and => cond = .{ .expr_and = try doubleHandside(alloc, command_parser, ast, idx, list) },
        .bool_or => cond = .{ .expr_or = try doubleHandside(alloc, command_parser, ast, idx, list) },
        .bool_not => {
            const node_data = ast.nodeData(idx).node;
            const lhs: *CondExpr = try alloc.create(CondExpr);
            errdefer alloc.destroy(lhs);
            lhs.* = try parseCondExpr(alloc, command_parser, ast, node_data, list);

            cond = .{ .not_expr = .{ .@"0" = lhs } };
        },
        .greater_than => cond = .{
            .greater = try doubleHandside(alloc, command_parser, ast, idx, list),
        },
        .greater_or_equal => cond = .{
            .greater_or_equal = try doubleHandside(alloc, command_parser, ast, idx, list),
        },
        .less_than => cond = .{
            .less = try doubleHandside(alloc, command_parser, ast, idx, list),
        },
        .less_or_equal => cond = .{
            .less_or_equal = try doubleHandside(alloc, command_parser, ast, idx, list),
        },
        .equal_equal => cond = .{
            .equal = try doubleHandside(alloc, command_parser, ast, idx, list),
        },
        .bang_equal => cond = .{
            .diff = try doubleHandside(alloc, command_parser, ast, idx, list),
        },
        else => unreachable,
    }

    return cond;
}

pub fn doubleHandside(
    alloc: std.mem.Allocator,
    command_parser: *Command.Parser,
    ast: Ast,
    idx: Ast.Node.Index,
    list: *std.ArrayList(Command),
) ParseError!struct { *CondExpr, *CondExpr } {
    const node_data = ast.nodeData(idx).node_and_node;
    const lhs: *CondExpr = try alloc.create(CondExpr);
    errdefer alloc.destroy(lhs);
    lhs.* = try parseCondExpr(alloc, command_parser, ast, node_data[0], list);

    const rhs: *CondExpr = try alloc.create(CondExpr);
    errdefer alloc.destroy(rhs);
    rhs.* = try parseCondExpr(alloc, command_parser, ast, node_data[1], list);

    return .{ .@"0" = lhs, .@"1" = rhs };
}

// TODO: Support:
//       + payload item
//       + slices: for(arr)
fn parseForNode(
    alloc: std.mem.Allocator,
    command_parser: *Command.Parser,
    ast: Ast,
    idx: Ast.Node.Index,
    list: *std.ArrayList(Command),
) !void {
    const node_data = ast.nodeData(idx).node_and_node;

    const item_count = list.items.len;
    const default: Command = get_default_cmd: {
        const cond_expr_idx = node_data[0];
        const cond_node_tag = ast.nodeTag(cond_expr_idx);
        const cond_node_data = ast.nodeData(cond_expr_idx).node_and_opt_node;
        // TODO: remove this assert
        std.debug.assert(cond_node_tag == .for_range);

        const lhs_str = ast.tokenSlice(ast.nodeMainToken(cond_node_data[0]));
        const lhs = try std.fmt.parseInt(usize, lhs_str, 10);
        const rhs_str = ast.tokenSlice(ast.nodeMainToken(cond_node_data[1].unwrap().?));
        const rhs = try std.fmt.parseInt(usize, rhs_str, 10);
        break :get_default_cmd .{
            .@"for" = .{
                .start_idx = item_count,
                .condition = .{
                    .range = .{ .start = lhs, .end = rhs },
                },
            },
        };
    };
    try list.append(alloc, default);

    const semi_node_idx = node_data[1];
    _ = try parseBlockNode(alloc, command_parser, ast, semi_node_idx, list);

    try list.append(alloc, .{ .end_loop = {} });
}

fn extractErrorFromAst(
    alloc: std.mem.Allocator,
    interpreter: *Interpreter,
    ast: Ast,
) !void {
    if (ast.errors.len > 0) {
        var list: std.ArrayList([]const u8) = .empty;
        var allocating_writer: std.Io.Writer.Allocating = .init(alloc);

        for (ast.errors) |err| {
            try ast.renderError(err, &allocating_writer.writer);
            try list.append(alloc, try allocating_writer.toOwnedSlice());
        }

        try interpreter.appendError(alloc, .{
            .tag = .from_languages,
            .extra = .{
                .from_languages = try list.toOwnedSlice(alloc),
            },
            .token = "",
        });
    }
}

test "(zig) parse command: calling functions" {
    const alloc = std.testing.allocator;
    var interpreter: Interpreter = .{};

    const src1 =
        \\pub fn main() void {}
    ;

    const cmds1 = try parse(alloc, &interpreter, src1);
    defer alloc.free(cmds1);
    try std.testing.expectEqual(0, cmds1.len);

    const src2 =
        \\pub fn () void {}
    ;
    const cmds2 = try parse(alloc, &interpreter, src2);
    defer alloc.free(cmds2);

    const err2: Interpreter.Error = .{
        .tag = .main_not_found,
        .token = "",
    };
    try std.testing.expectEqual(1, interpreter.errors.items.len);
    try std.testing.expectEqual(err2, interpreter.errors.items[0]);
    interpreter.errors.shrinkAndFree(alloc, 0); // reset errors

    const src3 =
        \\pub fn main() void {
        \\  move(.up);
        \\  move(.down);
        \\  move(.left);
        \\  move(.right);
        \\}
    ;
    const cmds3 = try parse(alloc, &interpreter, src3);
    defer alloc.free(cmds3);
    try std.testing.expectEqual(4, cmds3.len);
    try std.testing.expectEqual(.up, cmds3[0].move);
    try std.testing.expectEqual(.down, cmds3[1].move);
    try std.testing.expectEqual(.left, cmds3[2].move);
    try std.testing.expectEqual(.right, cmds3[3].move);
    interpreter.errors.shrinkAndFree(alloc, 0); // reset errors
}

test "(zig) parse command: if statement" {
    var interpreter: Interpreter = .{};
    const alloc = std.testing.allocator;

    const src1 =
        \\pub fn main() void {
        \\  if(true) {
        \\     move(.down);
        \\  }
        \\
        \\  if(false) {
        \\     move(.down);
        \\  }
        \\}
    ;
    const cmds1 = try parse(alloc, &interpreter, src1);
    defer alloc.free(cmds1);

    // NOTE: 4 ingame commands & 2 jump commands
    try std.testing.expectEqual(6, cmds1.len);
    try std.testing.expectEqual(
        Command.info.If{
            .condition = .{ .literal = true },
            .then_num_cmds = 2,
            .else_num_cmds = 0,
        },
        cmds1[0].@"if",
    );
    try std.testing.expectEqual(.down, cmds1[1].move);
    try std.testing.expectEqual(
        Command.info.If{
            .condition = .{ .literal = false },
            .then_num_cmds = 2,
            .else_num_cmds = 0,
        },
        cmds1[3].@"if",
    );
    try std.testing.expectEqual(.down, cmds1[4].move);
}
