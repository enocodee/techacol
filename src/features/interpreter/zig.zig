const std = @import("std");

const Interpreter = @import("Interpreter.zig");

const Command = Interpreter.Command;
const Ast = std.zig.Ast;

// Contains all called functions in the main
const MainNode = std.ArrayList(Node);

const Node = struct {
    fn_name: []const u8,
    arg_value: []const u8,
    arg_node_tag: Ast.Node.Tag,
};

pub fn parse(
    alloc: std.mem.Allocator,
    interpreter: *Interpreter,
    source: [:0]const u8,
) ![]Command {
    var commands: std.ArrayList(Command) = .empty;
    const command_parser: Command.Parser = .init(alloc, interpreter);
    const ast = try Ast.parse(alloc, source, .zig);

    try extractErrorFromAst(alloc, interpreter, ast);
    if (interpreter.errors.items.len > 0) return &.{};

    const main = (try parseMainNode(
        alloc,
        interpreter,
        ast,
    )) orelse return &.{};

    for (main.items) |node| {
        const command = try command_parser.parse(
            node.fn_name,
            node.arg_value,
            node.arg_node_tag,
        );

        try commands.append(alloc, command);
    }
    return commands.toOwnedSlice(alloc);
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
/// This function can cause to panic due to out of memory.
fn parseMainNode(
    alloc: std.mem.Allocator,
    interpreter: *Interpreter,
    ast: Ast,
) !?MainNode {
    var nodes: MainNode = .empty;
    // TODO: enable user to declare custom functions, variables, ..., like normal.
    // NOTE: currently, players can only declare the `main` function
    //       and use available functions ingame.

    // get main node (`fn main()`)
    const main_node_idx = getMainNodeIdx(ast) orelse {
        try interpreter.appendError(alloc, .{
            .tag = .main_not_found,
            .token = "",
        });
        return null;
    };

    const block_node_idx = ast.nodeData(main_node_idx).node_and_node[1];
    // get nodes in main body
    var call_node_buf: [2]Ast.Node.Index = undefined;
    const call_node_idxs = ast.blockStatements(&call_node_buf, block_node_idx).?;

    for (call_node_idxs) |idx| {
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

        try nodes.append(alloc, .{
            .fn_name = fn_name,
            .arg_value = arg_value,
            .arg_node_tag = arg_node_tag,
        });
    }
    return nodes;
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

test "parse action (zig)" {
    var interpreter: Interpreter = .{};

    // simulate the `World.arena`
    var base_alloc = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer base_alloc.deinit();
    const alloc = base_alloc.allocator();

    const src1 =
        \\pub fn main() void {}
    ;

    const cmds1 = try parse(alloc, &interpreter, src1);
    try std.testing.expectEqual(0, cmds1.len);

    const src2 =
        \\pub fn () void {}
    ;
    _ = try parse(alloc, &interpreter, src2);
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
    try std.testing.expectEqual(4, cmds3.len);
    try std.testing.expectEqual(.up, cmds3[0].move);
    try std.testing.expectEqual(.down, cmds3[1].move);
    try std.testing.expectEqual(.left, cmds3[2].move);
    try std.testing.expectEqual(.right, cmds3[3].move);
    interpreter.errors.shrinkAndFree(alloc, 0); // reset errors
}
