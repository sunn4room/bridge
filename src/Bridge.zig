const std = @import("std");

const WindowManager = @import("WindowManager.zig");
const XkbBindingManager = @import("XkbBindingManager.zig");
const LayerShellManager = @import("LayerShellManager.zig");

const Self = @This();

window_manager: ?*WindowManager = null,
xkb_binding_manager: ?*XkbBindingManager = null,
layer_shell_manager: ?*LayerShellManager = null,
running: bool = true,

pub fn create() *Self {
    const bridge = std.heap.c_allocator.create(Self) catch unreachable;
    bridge.* = .{};
    return bridge;
}

pub fn destroy(self: *Self) void {
    if (self.window_manager) |window_manager| window_manager.destroy();
    if (self.xkb_binding_manager) |xkb_binding_manager| xkb_binding_manager.destroy();
    if (self.layer_shell_manager) |layer_shell_manager| layer_shell_manager.destroy();
    std.heap.c_allocator.destroy(self);
}
