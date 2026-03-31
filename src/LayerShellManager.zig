const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const util = @import("util.zig");
const Bridge = @import("Bridge.zig");

const Self = @This();

handle: *river.LayerShellV1,
handle_name: u32,
bridge: *Bridge,

pub fn inject(handle: *river.LayerShellV1, handle_name: u32, bridge: *Bridge) void {
    const layer_shell_manager = std.heap.c_allocator.create(Self) catch unreachable;
    layer_shell_manager.* = .{
        .handle = handle,
        .handle_name = handle_name,
        .bridge = bridge,
    };
    bridge.layer_shell_manager = layer_shell_manager;
    util.log.debug("{f} has been created.", .{layer_shell_manager});
}

pub fn destroy(self: *Self) void {
    util.log.debug("{f} is about to be destroyed.", .{self});
    self.handle.destroy();
    self.bridge.layer_shell_manager = null;
    std.heap.c_allocator.destroy(self);
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("layer_shell_manager#{d}", .{self.handle.getId()});
}
