const std = @import("std");

/// From `features.digger.utils.action.MoveDirection`
/// to`digger.MoveDirection`
///
/// From `features.terminal.action.Debug`
/// to`terminal.Debug`
///
/// This function asserts that the string must be a valid format:
/// * `features.<object-name>.<...>.<ActionType>`
pub fn normalizedActionType(
    alloc: std.mem.Allocator,
    str: []const u8,
) ![]const u8 {
    var iter = std.mem.splitScalar(u8, str, '.');
    _ = iter.first(); // skip `features`
    const object = iter.next().?; // get the main object
    var action_type: []const u8 = undefined;

    std.debug.assert(iter.rest().len > 0);
    while (iter.next()) |a| {
        action_type = a;
    }

    return std.mem.concat(alloc, u8, &[_][]const u8{
        object, ".", action_type,
    });
}

test "normalized action type" {
    const alloc = std.testing.allocator;

    const str1 = "features.digger.utils.action.MoveDirection";
    const normalized1 = try normalizedActionType(alloc, str1);
    defer alloc.free(normalized1);

    try std.testing.expectEqualStrings(
        "digger.MoveDirection",
        normalized1,
    );
}

/// The caller should `free` the return value.
/// Normalized the source code:
/// * Trimming.
/// * Remove null-character.
pub fn normalizedSource(alloc: std.mem.Allocator, source: []const u8) ![:0]const u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(alloc);
    const trimmed = std.mem.trim(u8, source, " ");

    for (trimmed) |c| {
        if (c != 0) {
            try list.append(alloc, c);
        }
    }
    return list.toOwnedSliceSentinel(alloc, 0);
}

test "normalized source" {
    const alloc = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(alloc);

    try list.appendSlice(alloc, "pub fn main() void {\r\n");
    try list.appendSlice(alloc, &[_]u8{ 0, 0, 0 });
    try list.appendSlice(alloc, "print(Hello World);\r\n");
    try list.appendSlice(alloc, &[_]u8{ 0, 0, 0 });
    try list.appendSlice(alloc, "}");
    try list.appendSlice(alloc, &[_]u8{ 0, 0, 0 });
    try std.testing.expectEqual(53, list.items.len);

    const source = try list.toOwnedSlice(alloc);
    defer alloc.free(source);

    const normalized = try normalizedSource(alloc, source);
    defer alloc.free(normalized);

    try std.testing.expectEqualStrings(
        "pub fn main() void {\r\nprint(Hello World);\r\n}",
        normalized,
    );
    try std.testing.expectEqual(44, normalized.len);
}
