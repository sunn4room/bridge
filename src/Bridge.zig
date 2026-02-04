const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;
const Modifiers = river.SeatV1.Modifiers;
const xkbcommon = @import("xkbcommon");
const Keysym = xkbcommon.Keysym;

const WindowManager = @import("WindowManager.zig");
const XkbBindingManager = @import("XkbBindingManager.zig");

const Self = @This();

window_manager: *WindowManager = undefined,
xkb_binding_manager: *XkbBindingManager = undefined,
running: bool = true,

pub fn create(
    window_manager_handle: *river.WindowManagerV1,
    xkb_binding_manager_handle: *river.XkbBindingsV1,
) *Self {
    const bridge = std.heap.c_allocator.create(Self) catch unreachable;
    bridge.* = .{};
    WindowManager.inject(window_manager_handle, bridge);
    XkbBindingManager.inject(xkb_binding_manager_handle, bridge);
    return bridge;
}

pub fn destroy(self: *Self) void {
    self.window_manager.destroy();
    self.xkb_binding_manager.destroy();
    std.heap.c_allocator.destroy(self);
}

pub fn quit(self: *Self) void {
    self.running = false;
}
