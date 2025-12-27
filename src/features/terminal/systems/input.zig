const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");

const Terminal = @import("../mod.zig").Terminal;
const Buffer = @import("../mod.zig").Buffer;
const Executor = @import("../../command_executor/mod.zig").CommandExecutor;
const Interpreter = @import("../../interpreter/Interpreter.zig");
const Query = ecs.query.Query;
const World = @import("ecs").World;
const With = @import("ecs").query.With;
const Grid = @import("ecs").common.Grid;

/// Running all available cmds in queue
pub fn execCmds(
    w: *World,
    queries: Query(&.{ *Executor, With(&.{Terminal}) }),
) !void {
    const executor = queries.single()[0];
    try executor.execNext(w, 1000);
}

pub fn handleKeys(
    alloc: std.mem.Allocator,
    grid: Grid,
    buf: *Buffer,
) !void {
    if (try handleTyping(alloc, grid, buf)) return;

    try handleBackspace(alloc, grid, buf);
    handleCursor(buf);

    // TODO: handle key combination
    const pressed = rl.getKeyPressed();
    if (pressed != .null) {
        switch (pressed) {
            .enter => try buf.newLine(alloc, grid),
            else => {},
        }
    }
}

fn handleBackspace(alloc: std.mem.Allocator, grid: Grid, buf: *Buffer) !void {
    if (rl.isKeyPressedRepeat(.backspace) or
        rl.isKeyPressed(.backspace))
    {
        try buf.remove(alloc, grid);
    }
}

fn handleCursor(buf: *Buffer) void {
    if (rl.isKeyPressedRepeat(.left) or
        rl.isKeyPressed(.left))
    {
        buf.seek(.left);
    }
    if (rl.isKeyPressedRepeat(.right) or
        rl.isKeyPressed(.right))
    {
        buf.seek(.right);
    }
    if (rl.isKeyPressedRepeat(.up) or
        rl.isKeyPressed(.up))
    {
        buf.seek(.up);
    }
    if (rl.isKeyPressedRepeat(.down) or
        rl.isKeyPressed(.down))
    {
        buf.seek(.down);
    }
}

/// Return `true` if typing
pub fn handleTyping(
    alloc: std.mem.Allocator,
    grid: Grid,
    buf: *Buffer,
) !bool {
    var key_int = rl.getCharPressed();

    while (key_int != 0) : (key_int = rl.getCharPressed()) {
        // allow range 32..127 chars in unicode
        if (key_int >= 32 and key_int < 127) {
            try buf.insert(alloc, grid, @as(u8, @intCast(key_int)));
        }
    }

    return key_int != 0;
}

pub fn process(
    w: *World,
    alloc: std.mem.Allocator,
    content: []const u8,
    lang: Interpreter.Language,
) !void {
    var executor = (try w.query(&.{ *Executor, With(&.{Terminal}) })).single()[0];
    var interpreter: Interpreter = .{};

    const cmds = try interpreter.parse(alloc, content, lang);
    defer alloc.free(cmds);

    for (cmds) |cmd| {
        try executor.enqueue(cmd);
    }
}
