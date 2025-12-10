const std = @import("std");
const rl = @import("raylib");

const Language = @import("../interpreter/Interpreter.zig").Language;

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
