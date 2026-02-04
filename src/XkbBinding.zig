const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;
const xkbcommon = @import("xkbcommon");

const util = @import("util.zig");
const Binding = util.Binding;
const Action = util.Action;
const Seat = @import("Seat.zig");

const Self = @This();

handle: *river.XkbBindingV1,
seat: *Seat,
action: Action,
link: wl.list.Link = undefined,

fn river_xkb_binding_listener(
    _: *river.XkbBindingV1,
    event: river.XkbBindingV1.Event,
    self: *Self,
) void {
    switch (event) {
        .pressed => {
            self.seat.action = self.action;
        },
        else => {
            util.log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
}

pub fn inject(handle: *river.XkbBindingV1, seat: *Seat, action: Action) void {
    const xkb_binding = std.heap.c_allocator.create(Self) catch unreachable;
    handle.setListener(*Self, river_xkb_binding_listener, xkb_binding);
    xkb_binding.* = .{
        .handle = handle,
        .seat = seat,
        .action = action,
    };
    seat.xkb_bindings.append(xkb_binding);
    util.log.debug("{f} has been created.", .{xkb_binding});
}

pub fn destroy(self: *Self) void {
    util.log.debug("{f} is about to be destroyed.", .{self});
    self.handle.destroy();
    self.link.remove();
    std.heap.c_allocator.destroy(self);
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("xkb_binding#{d}", .{self.handle.getId()});
}
