const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const config = @import("config.zig");
const util = @import("util.zig");
const log = util.log;
const WindowManager = @import("WindowManager.zig");
const Output = @import("Output.zig");

const Self = @This();

window_manager: *WindowManager,
river_window: *river.WindowV1,
node: *river.NodeV1,
link: wl.list.Link = undefined,
new: bool = true,
dirty: bool = false,
focused: bool = false,
visible: bool = false,
output: ?*Output = null,
weight: i32 = 5,
sticky: bool = false,
lock: bool = false,

pub fn bind(window_manager: *WindowManager, river_window: *river.WindowV1) void {
    const self = std.heap.c_allocator.create(Self) catch unreachable;
    river_window.setListener(*Self, river_window_listener, self);
    self.* = .{
        .window_manager = window_manager,
        .river_window = river_window,
        .node = river_window.getNode() catch unreachable,
    };
    self.link.init();
    window_manager.windows.append(self);
    var output: ?*Output = null;
    if (window_manager.windows.last()) |last_window| {
        if (last_window.output) |last_window_output| output = last_window_output;
    }
    if (output == null) output = window_manager.outputs.first();
    self.send(output);
    var seat_iterator = window_manager.seats.iterator(.forward);
    while (seat_iterator.next()) |seat| seat.focus(self);
    log.debug("{f} has been created.", .{self});
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});
    self.send(null);
    var fallback: ?*Self = null;
    if (self.output) |output| {
        var each_window = self.iterate(.reverse);
        while (each_window != self.window_manager.windows.last()) : (each_window = each_window.iterate(.reverse)) {
            if (each_window.output == output) {
                fallback = each_window;
                break;
            }
        }
    }
    self.link.remove();
    if (fallback == null) fallback = self.window_manager.windows.last();
    var seat_iterator = self.window_manager.seats.iterator(.forward);
    while (seat_iterator.next()) |seat| if (seat.window == self) seat.focus(fallback);
    self.node.destroy();
    self.river_window.destroy();
    std.heap.c_allocator.destroy(self);
}

pub fn iterate(self: *Self, dir: wl.list.Direction) *Self {
    var link: *wl.list.Link = &self.link;
    return while (true) {
        link = switch (dir) {
            .forward => link.next.?,
            .reverse => link.prev.?,
        };
        if (link == &self.window_manager.windows.link) continue;
        break @fieldParentPtr("link", link);
    };
}

pub fn manage(self: *Self) void {
    if (self.new) {
        self.river_window.useSsd();
        self.new = false;
    }

    if (self.dirty) {
        defer log.debug("{f} has updated state.", .{self});

        self.focused = false;
        var seat_iterator = self.window_manager.seats.iterator(.forward);
        while (seat_iterator.next()) |seat| {
            if (seat.window == self) {
                seat.river_seat.focusWindow(self.river_window);
                self.focused = true;
            }
        }
        if (self.focused) {
            self.river_window.setBorders(
                .{ .top = true, .bottom = true, .left = true, .right = true },
                config.border_width,
                config.border_focused.r,
                config.border_focused.g,
                config.border_focused.b,
                config.border_focused.a,
            );
        } else {
            self.river_window.setBorders(
                .{ .top = true, .bottom = true, .left = true, .right = true },
                config.border_width,
                config.border_normal.r,
                config.border_normal.g,
                config.border_normal.b,
                config.border_normal.a,
            );
        }
        if (self.focused or self.sticky) {
            self.river_window.show();
            self.visible = true;
        } else {
            self.river_window.hide();
            self.visible = false;
        }

        self.dirty = false;
    }
}

pub fn changeWeight(self: *Self, step: i32) void {
    const old_weight = self.weight;
    self.weight += step;
    if (self.weight < 1) {
        self.weight = 1;
    } else if (self.weight > 10) {
        self.weight = 10;
    }
    if (self.weight != old_weight and self.visible) {
        if (self.output) |output| output.dirty = true;
    }
}

pub fn setSticky(self: *Self, sticky: bool) void {
    if (self.sticky == sticky) return;
    self.sticky = sticky;
    if (!self.focused) {
        self.dirty = true;
        if (self.output) |output| output.dirty = true;
    }
}

pub fn send(self: *Self, output: ?*Output) void {
    if (self.output == output) return;
    if (self.visible) {
        if (self.output) |old_output| old_output.dirty = true;
    }
    self.output = output;
    if (self.visible) {
        if (self.output) |new_output| new_output.dirty = true;
    }
}

pub fn swap(self: *Self, another: *Self) void {
    if (self == another) return;
    self.link.swapWith(&another.link);
    if (self.visible) {
        if (self.output) |output| output.dirty = true;
    }
    if (another.visible) {
        if (another.output) |output| output.dirty = true;
    }
}

pub fn close(self: *Self) void {
    self.river_window.close();
}

fn river_window_listener(_: *river.WindowV1, event: river.WindowV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .closed => {
            self.destroy();
        },
        .dimensions,
        .dimensions_hint,
        .app_id,
        .title,
        .parent,
        .decoration_hint,
        .pointer_move_requested,
        .pointer_resize_requested,
        .show_window_menu_requested,
        .maximize_requested,
        .unmaximize_requested,
        .fullscreen_requested,
        .exit_fullscreen_requested,
        .minimize_requested,
        .unreliable_pid,
        => {
            log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("window#{d}", .{self.river_window.getId()});
}
