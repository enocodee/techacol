const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const components = @import("components.zig");

const World = ecs.World;
const Query = ecs.query.Query;
const Position = ecs.common.Position;
const Score = @import("../score/mod.zig").Score;
const DebugBox = components.DebugBox;
const DebugInfo = components.DebugInfo;

pub fn updateInfo(w: *World, queries: Query(&.{*DebugInfo})) !void {
    const score = try w.getResource(Score);
    const info = queries.single()[0];

    const rusage = std.posix.getrusage(0);
    info.* = .{
        .memory_usage = @as(i32, @intCast(rusage.maxrss)),
        .score = score.amount,
    };
}

pub fn render(queries: Query(&.{ DebugBox, DebugInfo })) !void {
    for (queries.result) |q| {
        const box, const info = q;

        box.draw(&.{
            "Memory usage",
            "Score",
        }, .{
            info.memory_usage,
            info.score,
        });
    }
}
