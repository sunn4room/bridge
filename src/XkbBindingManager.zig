const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const util = @import("util.zig");
const Bridge = @import("Bridge.zig");
const XkbBinding = @import("XkbBinding.zig");
const Seat = @import("Seat.zig");
const Modifiers = Seat.Modifiers;
const Keysym = Seat.Keysym;
const Action = Seat.Action;

const Self = @This();

handle: *river.XkbBindingsV1,
bridge: *Bridge,

pub fn inject(handle: *river.XkbBindingsV1, bridge: *Bridge) void {
    const xkb_binding_manager = std.heap.c_allocator.create(Self) catch unreachable;
    xkb_binding_manager.* = .{
        .handle = handle,
        .bridge = bridge,
    };
    bridge.xkb_binding_manager = xkb_binding_manager;
    util.log.debug("{f} has been created.", .{xkb_binding_manager});
}

pub fn destroy(self: *Self) void {
    util.log.debug("{f} is about to be destroyed.", .{self});
    self.handle.destroy();
    std.heap.c_allocator.destroy(self);
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("xkb_binding_manager#{d}", .{self.handle.getId()});
}
