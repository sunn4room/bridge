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
river_pointer_binding: *river.PointerBindingV1,
action: Action,
link: wl.list.Link = undefined,

pub fn bind(seat: *Seat, river_pointer_binding: *river.PointerBindingV1, action: Action) void {
    const self = std.heap.c_allocator.create(Self) catch unreachable;
    river_pointer_binding.setListener(*Self, river_pointer_binding_listener, self);
    self.* = .{
        .seat = seat,
        .river_pointer_binding = river_pointer_binding,
        .action = action,
    };
    self.link.init();
    seat.pointer_bindings.append(self);
    log.debug("{f} has been created.", .{self});
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});
    self.link.remove();
    self.river_pointer_binding.destroy();
    std.heap.c_allocator.destroy(self);
}

fn river_pointer_binding_listener(_: *river.PointerBindingV1, event: river.PointerBindingV1.Event, self: *Self) void {
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
    try writer.print("pointer_binding#{d}", .{self.river_pointer_binding.getId()});
}
