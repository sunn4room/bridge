const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;

const util = @import("util.zig");
const log = util.log;
const WindowManager = @import("WindowManager.zig");

pub fn main() void {
    const wl_display = wl.Display.connect(null) catch {
        log.err("Failed to connect to wayland display.", .{});
        return;
    };
    defer wl_display.disconnect();

    const window_manager = WindowManager.create(wl_display);
    defer window_manager.destroy();

    while (window_manager.running) {
        if (wl_display.dispatch() != .SUCCESS) unreachable;
    }
}
