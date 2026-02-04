const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const util = @import("util.zig");
const Bridge = @import("Bridge.zig");

const Global = struct {
    river_window_manager: ?*river.WindowManagerV1 = null,
    river_window_manager_name: ?u32 = null,
    river_xkb_bindings: ?*river.XkbBindingsV1 = null,
    river_xkb_bindings_name: ?u32 = null,
    river_layer_shell: ?*river.LayerShellV1 = null,
    river_layer_shell_name: ?u32 = null,
};

fn wayland_display_registry_listener(
    registry: *wl.Registry,
    event: wl.Registry.Event,
    global: *Global,
) void {
    switch (event) {
        .global => |data| {
            if (std.mem.orderZ(u8, data.interface, river.WindowManagerV1.interface.name) == .eq) {
                global.river_window_manager = registry.bind(data.name, river.WindowManagerV1, 4) catch unreachable;
                global.river_window_manager_name = data.name;
            } else if (std.mem.orderZ(u8, data.interface, river.XkbBindingsV1.interface.name) == .eq) {
                global.river_xkb_bindings = registry.bind(data.name, river.XkbBindingsV1, 2) catch unreachable;
                global.river_xkb_bindings_name = data.name;
            } else if (std.mem.orderZ(u8, data.interface, river.LayerShellV1.interface.name) == .eq) {
                global.river_layer_shell = registry.bind(data.name, river.LayerShellV1, 1) catch unreachable;
                global.river_layer_shell_name = data.name;
            }
        },
        .global_remove => |data| {
            if (data.name == global.river_window_manager_name or data.name == global.river_xkb_bindings_name or data.name == global.river_layer_shell_name) unreachable;
        },
    }
}

pub fn main() !void {
    const wayland_display = try wl.Display.connect(null);
    defer wayland_display.disconnect();

    const wayland_display_registry = wayland_display.getRegistry() catch unreachable;
    defer wayland_display_registry.destroy();

    var global: Global = .{};
    wayland_display_registry.setListener(*Global, wayland_display_registry_listener, &global);
    if (wayland_display.roundtrip() != .SUCCESS) unreachable;

    const window_manager_handle = global.river_window_manager orelse return error.RiverWindowManagerNotAdvertised;
    errdefer window_manager_handle.destroy();
    const xkb_binding_manager_handle = global.river_xkb_bindings orelse return error.RiverXkbBindingsNotAdvertised;
    errdefer xkb_binding_manager_handle.destroy();
    const layer_shell_manager = global.river_window_manager orelse return error.RiverLayerShellNotAdvertised;
    errdefer layer_shell_manager.destroy();

    util.log.debug("Welcome!", .{});
    defer util.log.debug("Bye!", .{});

    const bridge = Bridge.create(
        window_manager_handle,
        xkb_binding_manager_handle,
    );
    defer bridge.destroy();

    while (bridge.running) {
        if (wayland_display.dispatch() != .SUCCESS) unreachable;
    }
}
