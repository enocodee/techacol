const std = @import("std");

/// Skip `chars` in `str` until the first character is found that
/// is **different** from **the first elements in `chars`**.
/// Return the number of characters skipped.
///
/// Example:
/// skipChar("abc\r", "\r\n")   -> 0: `\r != \r\n`
/// skipChar("abc\r", "\r")     -> 1: `\r == \r`
///
/// skipChar("abc\r\n", "\r")   -> 0: `\n != \r`
/// skipChar("abc\r\n", "\r\n") -> 2
/// skipChar("abc\n\r", "\r")   -> 0: `\r\n != \r`
///
/// skipChar("abc", "\r")       -> 0:
pub fn skipChar(str: []const u8, chars: []const u8) i32 {
    if (str.len == 0) return 0;
    var end: isize = @intCast(str.len);
    // enable `idx` to be negative to end the loop
    var start = end - @as(isize, @intCast(chars.len));
    var count: usize = 0;

    while (start >= 0) {
        if (std.mem.eql(
            u8,
            str[@intCast(start)..@intCast(end)],
            chars,
        )) {
            count += 1;
        } else break;

        end = start;
        start = end - @as(isize, @intCast(chars.len));
    }
    return @intCast(count * chars.len);
}

test "skip characters" {
    const str1 = "abc\r\n";
    const skip1 = skipChar(str1, "\r\n");
    try std.testing.expectEqual(2, skip1);

    const str2 = "abc\r\n";
    const skip2 = skipChar(str2, "\n");
    try std.testing.expectEqual(1, skip2);

    const str3 = &[_]u8{0} ** 10;
    var mutable_str = @constCast(str3);
    mutable_str[6] = 'A';
    mutable_str[7] = '\r';

    const skip3 = skipChar(str3, &[_]u8{0});
    try std.testing.expectEqual(2, skip3);

    const skip4 = skipChar(str3[0 .. str3.len - @as(usize, @intCast(skip3))], "\r");
    try std.testing.expectEqual(1, skip4);

    mutable_str[8] = '\n';

    const skip5 = skipChar(str3, &[_]u8{0});
    try std.testing.expectEqual(1, skip5);

    const skip6 = skipChar(str3[0 .. str3.len - @as(usize, @intCast(skip5))], "\r\n");
    try std.testing.expectEqual(2, skip6);
}

/// Increase the list item length by 1 and right-shift all
/// items after from index `i`, then insert an `item` at
/// index `i` in list.
pub fn insertAndShiftMemory(
    alloc: std.mem.Allocator,
    comptime T: type,
    list: *std.ArrayList(T),
    i: usize,
    item: T,
) !void {
    try list.ensureTotalCapacity(alloc, list.items.len + 1);
    list.items.len += 1;
    @memmove(
        list.items[i + 1 .. list.items.len],
        list.items[i .. list.items.len - 1],
    );
    list.items[i] = item;
}
