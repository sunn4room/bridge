const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;
const Modifiers = river.SeatV1.Modifiers;
const xkbcommon = @import("xkbcommon");
const Keysym = xkbcommon.Keysym;
const fcft = @import("fcft");
const pixman = @import("pixman");

const config = @import("config.zig");

pub const log = std.log.scoped(.bridge);

pub const Color = struct {
    r: u32,
    g: u32,
    b: u32,
    a: u32,
};

pub fn getColor(u: u32) Color {
    return .{
        .r = ((u >> 24) & 0xff) * 0x01010101,
        .g = ((u >> 16) & 0xff) * 0x01010101,
        .b = ((u >> 8) & 0xff) * 0x01010101,
        .a = (u & 0xff) * 0x01010101,
    };
}

pub fn getPixmanColor(u: u32) pixman.Color {
    return .{
        .red = ((u >> 24) & 0xff) * 0x0101,
        .green = ((u >> 16) & 0xff) * 0x0101,
        .blue = ((u >> 8) & 0xff) * 0x0101,
        .alpha = (u & 0xff) * 0x0101,
    };
}

pub const Button = enum(u32) {
    left = 0x110,
    right = 0x111,
};

pub const Trigger = union(enum) {
    keysym: Keysym,
    button: Button,
};

pub const Action = union(enum) {
    toggle_passthrough,
    spawn: []const []const u8,
    toggle_window_sticky,
    toggle_window_fullscreen,
    iterate_window_weight: wl.list.Direction,
    iterate_window_focus: wl.list.Direction,
    iterate_sticky_window_focus: wl.list.Direction,
    iterate_window_order: wl.list.Direction,
    iterate_output_view: wl.list.Direction,
    iterate_output_focus: wl.list.Direction,
    iterate_window_output: wl.list.Direction,
    set_window_focus: i32,
    set_window_weight: i32,
    set_output_view: u4,
    close_window,
    quit,
};

pub const Binding = struct {
    modifiers: Modifiers,
    trigger: Trigger,
    action: Action,
};

pub const Rect = struct {
    x: i32,
    y: i32,
    w: u31,
    h: u31,
};

pub fn hit(x: i32, y: i32, rect: ?Rect) bool {
    if (rect) |nonull_rect| {
        if (x >= nonull_rect.x and y >= nonull_rect.y and x <= nonull_rect.x + nonull_rect.w and y <= nonull_rect.y + nonull_rect.h) {
            return true;
        } else {
            return false;
        }
    } else {
        return false;
    }
}

pub fn spawn(cmd: []const []const u8) void {
    var child = std.process.Child.init(cmd, std.heap.c_allocator);
    child.spawn() catch {};
}

pub fn getFont(dpi: u32) *fcft.Font {
    var names: [1][*:0]const u8 = .{config.font_name};
    const names_len: usize = 1;
    if (dpi > 999) unreachable;
    var attributes = [_]u8{0} ** 8;
    return fcft.Font.fromName(names[0..names_len], std.fmt.bufPrintZ(&attributes, "dpi={}", .{dpi}) catch unreachable) catch unreachable;
}
