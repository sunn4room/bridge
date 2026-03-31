const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const util = @import("util.zig");
const Bridge = @import("Bridge.zig");
const WindowManager = @import("WindowManager.zig");
const XkbBindingManager = @import("XkbBindingManager.zig");
const LayerShellManager = @import("LayerShellManager.zig");

fn wayland_display_registry_listener(registry: *wl.Registry, event: wl.Registry.Event, bridge: *Bridge) void {
    switch (event) {
        .global => |global| {
            if (std.mem.orderZ(u8, global.interface, river.WindowManagerV1.interface.name) == .eq) {
                const window_manager_handle = registry.bind(global.name, river.WindowManagerV1, 4) catch unreachable;
                WindowManager.inject(window_manager_handle, global.name, bridge);
            } else if (std.mem.orderZ(u8, global.interface, river.XkbBindingsV1.interface.name) == .eq) {
                const xkb_binding_manager_handle = registry.bind(global.name, river.XkbBindingsV1, 2) catch unreachable;
                XkbBindingManager.inject(xkb_binding_manager_handle, global.name, bridge);
            } else if (std.mem.orderZ(u8, global.interface, river.LayerShellV1.interface.name) == .eq) {
                const layer_shell_manager_handle = registry.bind(global.name, river.LayerShellV1, 1) catch unreachable;
                LayerShellManager.inject(layer_shell_manager_handle, global.name, bridge);
            }
        },
        .global_remove => |global| {
            if (bridge.window_manager != null and bridge.window_manager.?.handle_name == global.name) {
                bridge.window_manager.?.destroy();
            } else if (bridge.xkb_binding_manager != null and bridge.xkb_binding_manager.?.handle_name == global.name) {
                bridge.xkb_binding_manager.?.destroy();
            } else if (bridge.layer_shell_manager != null and bridge.layer_shell_manager.?.handle_name == global.name) {
                bridge.layer_shell_manager.?.destroy();
            }
        },
    }
}

pub fn main() void {
    const wayland_display = wl.Display.connect(null) catch return;

    util.log.info("Welcome!", .{});
    defer util.log.info("Bye!", .{});

    const bridge = Bridge.create();
    defer bridge.destroy();

    const wayland_display_registry = wayland_display.getRegistry() catch unreachable;
    wayland_display_registry.setListener(*Bridge, wayland_display_registry_listener, bridge);

    while (bridge.running) {
        if (wayland_display.dispatch() != .SUCCESS) unreachable;
    }
}
