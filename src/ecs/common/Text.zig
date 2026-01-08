const rl = @import("raylib");

const QueryToRender = @import("utils.zig").QueryToRender;
const Position = @import("position.zig").Position;

const Text = @This();

font: rl.Font,
content: Content,

pub const Content = union(enum) {
    allocated: [:0]const u8,
    str: [:0]const u8,

    pub fn value(self: Content) [:0]const u8 {
        switch (self) {
            .allocated, .str => |str| return str,
        }
    }
};

pub const Bundle = struct {
    text: Text,
    pos: Position,
};

/// See `initWithDefaultFont` to initialize the instace with
/// default font from raylib.
pub fn init(font: rl.Font, content: Content) Text {
    return .{
        .font = font,
        .content = content,
    };
}

pub fn deinit(
    self: Text,
    alloc: @import("std").mem.Allocator,
) void {
    switch (self.content) {
        .allocated => |str| alloc.free(str),
        else => {},
    }
}

pub fn initWithDefaultFont(content: Content) !Text {
    return .{
        .content = content,
        .font = try rl.getFontDefault(),
    };
}

pub fn render(queries: QueryToRender(&.{ Text, Position })) !void {
    for (queries.many()) |query| {
        const text, const pos = query;

        rl.drawTextEx(
            text.font,
            text.content.value(),
            .{ .x = @floatFromInt(pos.x), .y = @floatFromInt(pos.y) },
            @floatFromInt(text.font.baseSize - 9),
            0,
            .white,
        );
    }
}
