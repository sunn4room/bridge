const util = @import("util.zig");
const Binding = util.Binding;

pub const color_background = util.getColor(0x282A36FF);
pub const color_foreground = util.getColor(0xF8F8F2FF);
pub const color_selection = util.getColor(0x44475AFF);
pub const color_theme = util.getColor(0x8BE9FDFF);

pub const layout_gap: i32 = 10;
pub const border_width: i32 = 2;
pub const border_normal = color_selection;
pub const border_focused = color_theme;
pub const border_sticky = color_foreground;

pub const startup_cmds = [_][]const []const u8{
    &.{ "sh", "-c", "swaybg -m fill -i ~/.config/wallpaper" },
};

pub const terminal = "foot";
pub const launcher = "fuzzel";

pub const bindings = [_]Binding{
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .Escape },
        .action = .toggle_passthrough,
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .Return },
        .action = .{ .spawn = &.{terminal} },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .space },
        .action = .{ .spawn = &.{launcher} },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .s },
        .action = .toggle_window_sticky,
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .w },
        .action = .{ .iterate_window_weight = .reverse },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .w },
        .action = .{ .iterate_window_weight = .forward },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .l },
        .action = .{ .iterate_window_focus = .forward },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .h },
        .action = .{ .iterate_window_focus = .reverse },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .l },
        .action = .{ .iterate_sticky_window_focus = .forward },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .h },
        .action = .{ .iterate_sticky_window_focus = .reverse },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .l },
        .action = .{ .iterate_window_order = .forward },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .h },
        .action = .{ .iterate_window_order = .reverse },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .j },
        .action = .{ .iterate_output_view = .forward },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .k },
        .action = .{ .iterate_output_view = .reverse },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .n },
        .action = .{ .iterate_output_focus = .forward },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .p },
        .action = .{ .iterate_output_focus = .reverse },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .n },
        .action = .{ .iterate_window_output = .forward },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .p },
        .action = .{ .iterate_window_output = .reverse },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"1" },
        .action = .{ .set_window_focus = 1 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"2" },
        .action = .{ .set_window_focus = 2 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"3" },
        .action = .{ .set_window_focus = 3 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"4" },
        .action = .{ .set_window_focus = 4 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"5" },
        .action = .{ .set_window_focus = 5 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"6" },
        .action = .{ .set_window_focus = 6 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"7" },
        .action = .{ .set_window_focus = 7 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"8" },
        .action = .{ .set_window_focus = 8 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"9" },
        .action = .{ .set_window_focus = 9 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"0" },
        .action = .{ .set_window_focus = 10 },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"1" },
        .action = .{ .set_window_weight = 1 },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"2" },
        .action = .{ .set_window_weight = 2 },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"3" },
        .action = .{ .set_window_weight = 3 },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"4" },
        .action = .{ .set_window_weight = 4 },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"5" },
        .action = .{ .set_window_weight = 5 },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"6" },
        .action = .{ .set_window_weight = 6 },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"7" },
        .action = .{ .set_window_weight = 7 },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"8" },
        .action = .{ .set_window_weight = 8 },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"9" },
        .action = .{ .set_window_weight = 9 },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"0" },
        .action = .{ .set_window_weight = 10 },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .@"1" },
        .action = .{ .set_output_view = 1 },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .@"2" },
        .action = .{ .set_output_view = 2 },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .@"3" },
        .action = .{ .set_output_view = 3 },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .@"4" },
        .action = .{ .set_output_view = 4 },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .@"5" },
        .action = .{ .set_output_view = 5 },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .@"6" },
        .action = .{ .set_output_view = 6 },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .@"7" },
        .action = .{ .set_output_view = 7 },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .@"8" },
        .action = .{ .set_output_view = 8 },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .@"9" },
        .action = .{ .set_output_view = 9 },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .@"0" },
        .action = .{ .set_output_view = 10 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .d },
        .action = .close_window,
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .Escape },
        .action = .quit,
    },
};
