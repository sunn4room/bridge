const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const util = @import("util.zig");
const log = util.log;
const Binding = util.Binding;
const Action = util.Action;
const Seat = @import("Seat.zig");

const Self = @This();

seat: *Seat,
river_xkb_binding: *river.XkbBindingV1,
action: Action,
link: wl.list.Link = undefined,

pub fn bind(seat: *Seat, river_xkb_binding: *river.XkbBindingV1, action: Action) void {
    const self = std.heap.c_allocator.create(Self) catch unreachable;
    river_xkb_binding.setListener(*Self, river_xkb_binding_listener, self);
    self.* = .{
        .seat = seat,
        .river_xkb_binding = river_xkb_binding,
        .action = action,
    };
    self.link.init();
    seat.xkb_bindings.append(self);
    log.debug("{f} has been created.", .{self});
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});
    self.link.remove();
    self.river_xkb_binding.destroy();
    std.heap.c_allocator.destroy(self);
}

fn river_xkb_binding_listener(_: *river.XkbBindingV1, event: river.XkbBindingV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .pressed => {
            self.seat.action = self.action;
        },
        .released => {
            log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
}

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("xkb_binding#{d}", .{self.river_xkb_binding.getId()});
}
