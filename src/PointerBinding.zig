const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const util = @import("util.zig");
const Binding = util.Binding;
const Action = util.Action;
const Seat = @import("Seat.zig");

const Self = @This();

handle: *river.PointerBindingV1,
seat: *Seat,
action: Action,
link: wl.list.Link = undefined,

fn river_pointer_binding_listener(
    _: *river.PointerBindingV1,
    event: river.PointerBindingV1.Event,
    self: *Self,
) void {
    util.log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .pressed => {
            self.seat.action = self.action;
        },
        else => {
            util.log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
}

pub fn inject(handle: *river.PointerBindingV1, action: Action, seat: *Seat) void {
    const pointer_binding = std.heap.c_allocator.create(Self) catch unreachable;
    handle.setListener(*Self, river_pointer_binding_listener, pointer_binding);
    pointer_binding.* = .{
        .handle = handle,
        .action = action,
        .seat = seat,
    };
    seat.pointer_bindings.append(pointer_binding);
    util.log.debug("{f} has been created.", .{pointer_binding});
}

pub fn destroy(self: *Self) void {
    util.log.debug("{f} is about to be destroyed.", .{self});
    self.handle.destroy();
    self.link.remove();
    std.heap.c_allocator.destroy(self);
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("pointer_binding#{d}", .{self.handle.getId()});
}
