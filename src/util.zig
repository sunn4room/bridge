const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;
const Modifiers = river.SeatV1.Modifiers;
const xkbcommon = @import("xkbcommon");
const Keysym = xkbcommon.Keysym;

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

pub const Button = enum(u32) {
    left = 0x110,
    right = 0x111,
};

pub const Trigger = union(enum) {
    keysym: Keysym,
    button: Button,
};

pub const Action = union(enum) {
    nop,
    toggle_passthrough,
    spawn: []const []const u8,
    change_window_weight: i32,
    toggle_window_sticky: bool,
    focus_window: i32,
    iterate_window: wl.list.Direction,
    iterate_output: wl.list.Direction,
    swap_window: wl.list.Direction,
    send_window: wl.list.Direction,
    close_window,
    quit,
};

pub const Binding = struct {
    modifiers: Modifiers,
    trigger: Trigger,
    action: Action,
};

pub fn spawn(cmd: []const []const u8) void {
    var child = std.process.Child.init(cmd, std.heap.c_allocator);
    child.spawn() catch {};
}
