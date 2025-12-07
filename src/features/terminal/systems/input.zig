const std = @import("std");
const rl = @import("raylib");
const digger = @import("../../digger/mod.zig");
const utils = @import("../utils.zig");

const Terminal = @import("../components.zig").Terminal;
const Executor = @import("../components.zig").CommandExecutor;
const Interpreter = @import("../../interpreter/Interpreter.zig");
const World = @import("ecs").World;

/// Running all available cmds in queue
pub fn execCmds(w: *World, _: std.mem.Allocator) !void {
    const executor = (try w.query(&.{ *Executor, Terminal }))[0][0];
    try executor.execNext(w, 1000);
}

pub fn scan(
    out: []u8,
    width: i32,
    count: *i32,
    max_length: i32,
    ts_backspace: *i64,
) !void {
    var keyInt = rl.getCharPressed();

    while (keyInt != 0) : (keyInt = rl.getCharPressed()) {
        // allow range 32..127 chars in unicode
        if ((keyInt >= 32) and (keyInt < 127) and count.* < max_length) {
            count.* += 1;
            out[@intCast(count.* - 1)] = @intCast(keyInt);
        }
    }

    // handle key holding
    if ((std.time.microTimestamp() - ts_backspace.*) > @divTrunc(1000000, 10)) // 0.1s
    {
        if (rl.isKeyDown(.backspace) and
            (count.* > 0))
        {
            const count_v = count.*;
            // NOTE: remove the space of `ENTER`
            const count_zero = utils.skipChar(out[0..@intCast(count_v)], &[_]u8{0});
            var count_cr = utils.skipChar(out[0..@intCast(count_v - count_zero)], "\r\n");

            const total = count_zero + count_cr;

            ts_backspace.* = std.time.microTimestamp();
            count.* -= blk: {
                if (count_zero != 0 or count_cr != 0) {
                    break :blk total;
                } else {
                    break :blk 1;
                }
            };
            if (count_cr > 0) {
                while (count_cr > 0) : (count_cr -= 1) {
                    out[@intCast(count_v - count_zero)] = 0;
                }
            } else {
                out[@intCast(count.*)] = 0;
            }
        }

        if (rl.isKeyDown(.enter)) {
            ts_backspace.* = std.time.microTimestamp();
            const remaning_to_new_line = width - @mod(count.*, width);
            out[@intCast(count.*)] = '\r';
            out[@intCast(count.* + 1)] = '\n';
            count.* += remaning_to_new_line;
        }
    }
}

pub fn process(
    w: *World,
    alloc: std.mem.Allocator,
    content: []const u8,
    lang: Interpreter.Language,
) !void {
    var executor = (try w.query(&.{ *Executor, Terminal }))[0][0];
    var interpreter: Interpreter = .{};

    const cmds = try interpreter.parse(alloc, content, lang);
    defer alloc.free(cmds);

    for (cmds) |cmd| {
        try executor.enqueue(cmd);
    }
}
