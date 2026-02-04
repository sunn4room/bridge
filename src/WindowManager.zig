const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const util = @import("util.zig");
const config = @import("config.zig");
const Bridge = @import("Bridge.zig");
const Seat = @import("Seat.zig");
const Output = @import("Output.zig");
const Window = @import("Window.zig");

const Self = @This();

handle: *river.WindowManagerV1,
bridge: *Bridge,
outputs: wl.list.Head(Output, .link) = undefined,
windows: wl.list.Head(Window, .link) = undefined,
seats: wl.list.Head(Seat, .link) = undefined,

fn river_window_manager_listener(
    _: *river.WindowManagerV1,
    event: river.WindowManagerV1.Event,
    self: *Self,
) void {
    switch (event) {
        .seat => |data| Seat.inject(data.id, self),
        .output => |data| Output.inject(data.id, self),
        .window => |data| Window.inject(data.id, self),
        .manage_start => {
            util.log.debug("{f} has started manage sequence.", .{self});
            defer util.log.debug("{f} has finished manage sequence.", .{self});

            var seat_iterator = self.seats.iterator(.forward);
            while (seat_iterator.next()) |seat| seat.manage();

            var window_iterator = self.windows.iterator(.forward);
            while (window_iterator.next()) |window| window.manage();

            var output_iterator = self.outputs.iterator(.forward);
            while (output_iterator.next()) |output| output.manage();

            self.handle.manageFinish();
        },
        .render_start => self.handle.renderFinish(),
        else => {
            util.log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
}

pub fn inject(handle: *river.WindowManagerV1, bridge: *Bridge) void {
    const window_manager = std.heap.c_allocator.create(Self) catch unreachable;
    handle.setListener(*Self, river_window_manager_listener, window_manager);
    window_manager.* = .{
        .handle = handle,
        .bridge = bridge,
    };
    window_manager.outputs.init();
    window_manager.seats.init();
    window_manager.windows.init();
    bridge.window_manager = window_manager;
    util.log.debug("{f} has been created.", .{window_manager});
}

pub fn destroy(self: *Self) void {
    util.log.debug("{f} is about to be destroyed.", .{self});
    var output_iterator = self.outputs.iterator(.forward);
    while (output_iterator.next()) |output| output.destroy();
    var seat_iterator = self.seats.iterator(.forward);
    while (seat_iterator.next()) |seat| seat.destroy();
    var window_iterator = self.windows.iterator(.forward);
    while (window_iterator.next()) |window| window.destroy();
    self.handle.destroy();
    std.heap.c_allocator.destroy(self);
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("window_manager#{d}", .{self.handle.getId()});
}

pub fn quit(self: *Self) void {
    self.handle.exitSession();
}
