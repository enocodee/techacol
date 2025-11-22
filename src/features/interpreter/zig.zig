const std = @import("std");

const Interpreter = @import("Interpreter.zig");

const Command = Interpreter.Command;

const Ast = std.zig.Ast;

const Main = struct {
    fn_name: []const u8,
    arg_value: []const u8,
    arg_node_tag: Ast.Node.Tag,
};

pub fn parse(
    alloc: std.mem.Allocator,
    interpreter: *Interpreter,
    source: [:0]const u8,
) !Command {
    const command_parser: Command.Parser = .init(alloc, interpreter);
    const ast = try Ast.parse(alloc, source, .zig);

    try extractErrorFromAst(alloc, interpreter, ast);
    if (interpreter.errors.items.len > 0) return .none;

    const main = (try parseMainNode(
        alloc,
        interpreter,
        ast,
    )) orelse return .none;

    return command_parser.parse(
        main.fn_name,
        main.arg_value,
        main.arg_node_tag,
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
        std.log.debug("{s}", .{fn_name});
        if (std.mem.eql(u8, "main", fn_name)) return true;
    }
    return false;
}

fn parseMainNode(
    alloc: std.mem.Allocator,
    interpreter: *Interpreter,
    ast: Ast,
) !?Main {
    // TODO: enable user to declare custom functions, variables, ..., like normal.
    // NOTE: currently, players can only declare the `main` function
    //       and use available functions ingame.

    // get main node (`fn main()`)
    const main_node_idx = getMainNodeIdx(ast) orelse {
        interpreter.appendError(alloc, .{
            .tag = .main_not_found,
            .token = "",
        });
        return null;
    };

    const block_node_idx = ast.nodeData(main_node_idx).node_and_node[1];
    // get nodes in main body
    var call_node_buf: [2]Ast.Node.Index = undefined;
    const call_node_idxs = ast.blockStatements(&call_node_buf, block_node_idx).?;

    // NOTE: player can only do a action at a time
    //
    // get the first `call` node
    const idx = call_node_idxs[0];
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

    return .{
        .fn_name = fn_name,
        .arg_value = arg_value,
        .arg_node_tag = arg_node_tag,
    };
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

        interpreter.appendError(alloc, .{
            .tag = .from_languages,
            .extra = .{
                .from_languages = try list.toOwnedSlice(alloc),
            },
            .token = "",
        });
    }
}
