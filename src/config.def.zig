const std = @import("std");
const util = @import("util.zig");
const Binding = util.Binding;

pub const color_background: u32 = 0x282A36FF;
pub const color_foreground: u32 = 0xF8F8F2FF;
pub const color_selection: u32 = 0x44475AFF;
pub const color_theme: u32 = 0x8BE9FDFF;

pub var bar_background = util.getPixmanColor(color_background);
pub var bar_foreground = util.getPixmanColor(color_foreground);
pub var bar_selection = util.getPixmanColor(color_selection);
pub var bar_theme = util.getPixmanColor(color_theme);

pub const layout_gap: i32 = 10;
pub const border_width: i32 = 2;
pub const border_normal = util.getColor(color_selection);
pub const border_focused = util.getColor(color_theme);
pub const border_sticky = util.getColor(color_foreground);

pub const font_name: [*:0]const u8 = "sans-serif:size=14";
pub const box_icons = [_][*:0]const u8{ "  󰎡  ", "  󰎤  ", "  󰎧  ", "  󰎪  ", "  󰎭  ", "  󰎱  ", "  󰎳  ", "  󰎶  ", "  󰎹  ", "  󰎼  ", "  󰽽  " };
pub const boxes_icons = [_][*:0]const u8{ "  󰼎  ", "  󰼏  ", "  󰼐  ", "  󰼑  ", "  󰼒  ", "  󰼓  ", "  󰼔  ", "  󰼕  ", "  󰼖  ", "  󰼗  ", "  󰿪  " };
pub const app_icon_fallback = "    ";
pub const app_icons = [_]struct { id: [*:0]const u8, icon: [*:0]const u8 }{
    .{ .icon = "    ", .id = "firefox" },
    .{ .icon = "    ", .id = "chrome" },
    .{ .icon = "    ", .id = "chromium" },
    .{ .icon = "    ", .id = "microsoft-edge" },
    .{ .icon = "    ", .id = "alacritty" },
    .{ .icon = "    ", .id = "kitty" },
    .{ .icon = "    ", .id = "ghostty" },
    .{ .icon = "    ", .id = "wezterm" },
    .{ .icon = "    ", .id = "foot" },
    .{ .icon = "    ", .id = "footclient" },
    .{ .icon = "    ", .id = "mpv" },
};

pub const startup_cmds = [_][]const []const u8{
    &.{ "foot", "-s" },
};

pub const terminal = "footclient";
pub const launcher = "fuzzel";

pub const bindings = [_]Binding{
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .Escape },
        .action = .toggle_passthrough,
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .Return },
        .action = .{ .spawn = &.{terminal} },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .space },
        .action = .{ .spawn = &.{launcher} },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .s },
        .action = .toggle_window_sticky,
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .a },
        .action = .toggle_window_fullscreen,
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .w },
        .action = .{ .iterate_window_weight = .reverse },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .w },
        .action = .{ .iterate_window_weight = .forward },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .Tab },
        .action = .{ .iterate_window_focus = .forward },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .Tab },
        .action = .{ .iterate_window_focus = .reverse },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .l },
        .action = .{ .iterate_window_focus = .forward },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .h },
        .action = .{ .iterate_window_focus = .reverse },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .l },
        .action = .{ .iterate_sticky_window_focus = .forward },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .h },
        .action = .{ .iterate_sticky_window_focus = .reverse },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .l },
        .action = .{ .iterate_window_order = .forward },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .h },
        .action = .{ .iterate_window_order = .reverse },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .j },
        .action = .{ .iterate_output_view = .forward },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .k },
        .action = .{ .iterate_output_view = .reverse },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .n },
        .action = .{ .iterate_output_focus = .forward },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .p },
        .action = .{ .iterate_output_focus = .reverse },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .n },
        .action = .{ .iterate_window_output = .forward },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .p },
        .action = .{ .iterate_window_output = .reverse },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .@"1" },
        .action = .{ .set_window_focus = 1 },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .@"2" },
        .action = .{ .set_window_focus = 2 },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .@"3" },
        .action = .{ .set_window_focus = 3 },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .@"4" },
        .action = .{ .set_window_focus = 4 },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .@"5" },
        .action = .{ .set_window_focus = 5 },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .@"6" },
        .action = .{ .set_window_focus = 6 },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .@"7" },
        .action = .{ .set_window_focus = 7 },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .@"8" },
        .action = .{ .set_window_focus = 8 },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .@"9" },
        .action = .{ .set_window_focus = 9 },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .@"0" },
        .action = .{ .set_window_focus = 10 },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"1" },
        .action = .{ .set_window_weight = 1 },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"2" },
        .action = .{ .set_window_weight = 2 },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"3" },
        .action = .{ .set_window_weight = 3 },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"4" },
        .action = .{ .set_window_weight = 4 },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"5" },
        .action = .{ .set_window_weight = 5 },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"6" },
        .action = .{ .set_window_weight = 6 },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"7" },
        .action = .{ .set_window_weight = 7 },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"8" },
        .action = .{ .set_window_weight = 8 },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"9" },
        .action = .{ .set_window_weight = 9 },
    },
    .{
        .modifiers = .{ .mod4 = true, .ctrl = true },
        .trigger = .{ .keysym = .@"0" },
        .action = .{ .set_window_weight = 10 },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .@"1" },
        .action = .{ .set_output_view = 1 },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .@"2" },
        .action = .{ .set_output_view = 2 },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .@"3" },
        .action = .{ .set_output_view = 3 },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .@"4" },
        .action = .{ .set_output_view = 4 },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .@"5" },
        .action = .{ .set_output_view = 5 },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .@"6" },
        .action = .{ .set_output_view = 6 },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .@"7" },
        .action = .{ .set_output_view = 7 },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .@"8" },
        .action = .{ .set_output_view = 8 },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .@"9" },
        .action = .{ .set_output_view = 9 },
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .@"0" },
        .action = .{ .set_output_view = 10 },
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .keysym = .d },
        .action = .close_window,
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .button = .left },
        .action = .enable_window_floating,
    },
    .{
        .modifiers = .{ .mod4 = true },
        .trigger = .{ .button = .right },
        .action = .disable_window_floating,
    },
    .{
        .modifiers = .{ .mod4 = true, .shift = true },
        .trigger = .{ .keysym = .Escape },
        .action = .quit,
    },
};
