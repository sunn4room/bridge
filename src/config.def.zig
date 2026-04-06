const std = @import("std");
const wayland = @import("wayland");
const Modifiers = wayland.client.river.SeatV1.Modifiers;

const util = @import("util.zig");
const Binding = @import("Binding.zig");

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

const mod______: Modifiers = .{ .mod4 = true };
const mod_shift: Modifiers = .{ .mod4 = true, .shift = true };
const mod_ctrl_: Modifiers = .{ .mod4 = true, .ctrl = true };
pub const mappers = [_]Binding.Mapper{
    .{ .modifiers = mod______, .trigger = .{ .keysym = .Escape }, .action = .toggle_passthrough },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .Return }, .action = .{ .spawn = &.{terminal} } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .space }, .action = .{ .spawn = &.{launcher} } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .s }, .action = .toggle_window_sticky },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .a }, .action = .toggle_window_fullscreen },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .w }, .action = .{ .iterate_window_weight = .reverse } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .w }, .action = .{ .iterate_window_weight = .forward } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .Tab }, .action = .{ .iterate_window_focus = .forward } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .Tab }, .action = .{ .iterate_window_focus = .reverse } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .l }, .action = .{ .iterate_window_focus = .forward } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .h }, .action = .{ .iterate_window_focus = .reverse } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .l }, .action = .{ .iterate_sticky_window_focus = .forward } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .h }, .action = .{ .iterate_sticky_window_focus = .reverse } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .l }, .action = .{ .iterate_window_order = .forward } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .h }, .action = .{ .iterate_window_order = .reverse } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .j }, .action = .{ .iterate_output_view = .forward } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .k }, .action = .{ .iterate_output_view = .reverse } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .n }, .action = .{ .iterate_output_focus = .forward } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .p }, .action = .{ .iterate_output_focus = .reverse } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .n }, .action = .{ .iterate_window_output = .forward } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .p }, .action = .{ .iterate_window_output = .reverse } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .@"1" }, .action = .{ .set_output_view = 1 } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .@"2" }, .action = .{ .set_output_view = 2 } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .@"3" }, .action = .{ .set_output_view = 3 } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .@"4" }, .action = .{ .set_output_view = 4 } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .@"5" }, .action = .{ .set_output_view = 5 } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .@"6" }, .action = .{ .set_output_view = 6 } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .@"7" }, .action = .{ .set_output_view = 7 } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .@"8" }, .action = .{ .set_output_view = 8 } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .@"9" }, .action = .{ .set_output_view = 9 } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .@"0" }, .action = .{ .set_output_view = 10 } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .@"1" }, .action = .{ .set_window_focus = 1 } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .@"2" }, .action = .{ .set_window_focus = 2 } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .@"3" }, .action = .{ .set_window_focus = 3 } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .@"4" }, .action = .{ .set_window_focus = 4 } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .@"5" }, .action = .{ .set_window_focus = 5 } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .@"6" }, .action = .{ .set_window_focus = 6 } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .@"7" }, .action = .{ .set_window_focus = 7 } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .@"8" }, .action = .{ .set_window_focus = 8 } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .@"9" }, .action = .{ .set_window_focus = 9 } },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .@"0" }, .action = .{ .set_window_focus = 10 } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .@"1" }, .action = .{ .set_window_weight = 1 } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .@"2" }, .action = .{ .set_window_weight = 2 } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .@"3" }, .action = .{ .set_window_weight = 3 } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .@"4" }, .action = .{ .set_window_weight = 4 } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .@"5" }, .action = .{ .set_window_weight = 5 } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .@"6" }, .action = .{ .set_window_weight = 6 } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .@"7" }, .action = .{ .set_window_weight = 7 } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .@"8" }, .action = .{ .set_window_weight = 8 } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .@"9" }, .action = .{ .set_window_weight = 9 } },
    .{ .modifiers = mod_ctrl_, .trigger = .{ .keysym = .@"0" }, .action = .{ .set_window_weight = 10 } },
    .{ .modifiers = mod______, .trigger = .{ .keysym = .d }, .action = .close_window },
    .{ .modifiers = mod______, .trigger = .{ .button = .left }, .action = .enable_window_floating },
    .{ .modifiers = mod______, .trigger = .{ .button = .right }, .action = .disable_window_floating },
    .{ .modifiers = mod_shift, .trigger = .{ .keysym = .Escape }, .action = .quit },
};
