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
        .trigger = .{ .keysym = .w },
        .action = .{ .change_window_weight = -1 },
    },
    .{
        .modifiers = .{ .mod1 = true, .shift = true },
        .trigger = .{ .keysym = .w },
        .action = .{ .change_window_weight = 1 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .s },
        .action = .toggle_window_sticky,
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .l },
        .action = .{ .iterate_window = .forward },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .h },
        .action = .{ .iterate_window = .reverse },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .l },
        .action = .{ .swap_window = .forward },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .h },
        .action = .{ .swap_window = .reverse },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .n },
        .action = .{ .iterate_output = .forward },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .p },
        .action = .{ .iterate_output = .reverse },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .n },
        .action = .{ .send_window = .forward },
    },
    .{
        .modifiers = .{ .mod1 = true, .ctrl = true },
        .trigger = .{ .keysym = .p },
        .action = .{ .send_window = .reverse },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"1" },
        .action = .{ .focus_window = 1 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"2" },
        .action = .{ .focus_window = 2 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"3" },
        .action = .{ .focus_window = 3 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"4" },
        .action = .{ .focus_window = 4 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"5" },
        .action = .{ .focus_window = 5 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"6" },
        .action = .{ .focus_window = 6 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"7" },
        .action = .{ .focus_window = 7 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"8" },
        .action = .{ .focus_window = 8 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"9" },
        .action = .{ .focus_window = 9 },
    },
    .{
        .modifiers = .{ .mod1 = true },
        .trigger = .{ .keysym = .@"0" },
        .action = .{ .focus_window = 10 },
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
