const std = @import("std");
const rl = @import("raylib");

const Language = @import("../interpreter/Interpreter.zig").Language;

pub const Buffer = struct {
    char_count: i32 = 0,
    chars: [:0]u8,
    capacity: usize,

    pub fn init(alloc: std.mem.Allocator, size: usize) Buffer {
        const buf = alloc.allocSentinel(u8, size, 0) catch @panic("OOM");
        @memset(buf, 0);
        return .{
            .chars = buf,
            .capacity = size,
        };
    }

    pub fn deinit(self: *Buffer, alloc: std.mem.Allocator) void {
        alloc.free(self.chars);
    }
};

pub const State = struct {
    is_focused: bool = false,
    ts_backspace: i64 = 0,
    frame_counter: usize = 0,
    lang: Language = .plaintext,
    lang_box_is_opened: bool = false,
    selected_lang: i32 = 0,
    /// Status if the button is clickable .
    /// Set `false` to disable.
    active: bool = true,
};

pub const Style = struct {
    font: rl.Font,
    font_size: i32 = 10,
    bg_color: rl.Color = .black,
};
