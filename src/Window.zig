const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const config = @import("config.zig");
const util = @import("util.zig");
const log = util.log;
const Rect = util.Rect;
const WindowManager = @import("WindowManager.zig");
const Output = @import("Output.zig");

const Self = @This();

window_manager: *WindowManager,
river_window: *river.WindowV1,
river_node: *river.NodeV1,
link: wl.list.Link = undefined,
new: bool = true,
icon: [*:0]const u8 = config.app_icon_fallback,
dirty: bool = false,
weight: u4 = 5,
focused: bool = false,
visible: bool = false,
sticky: bool = false,
output: ?*Output = null,
views: u10 = 0,
buttons: [2]?Rect = .{null} ** 2,

pub fn bind(window_manager: *WindowManager, river_window: *river.WindowV1) void {
    const self = std.heap.c_allocator.create(Self) catch unreachable;
    river_window.setListener(*Self, river_window_listener, self);
    self.* = .{
        .window_manager = window_manager,
        .river_window = river_window,
        .river_node = river_window.getNode() catch unreachable,
    };

    var output: ?*Output = null;
    if (self.window_manager.windows.last()) |last_window| {
        if (last_window.output) |last_window_output| output = last_window_output;
    }

    self.link.init();
    window_manager.windows.append(self);

    if (output == null) output = window_manager.outputs.first();
    self.send(output);

    var seat_iterator = window_manager.seats.iterator(.forward);
    while (seat_iterator.next()) |seat| seat.focus(self);

    log.debug("{f} has been created.", .{self});
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

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
    self.send(null);

    if (fallback == null) fallback = self.window_manager.windows.last();
    var seat_iterator = self.window_manager.seats.iterator(.forward);
    while (seat_iterator.next()) |seat| if (seat.window == self) seat.focus(fallback);

    self.river_node.destroy();
    self.river_window.destroy();
    std.heap.c_allocator.destroy(self);
}

fn river_window_listener(_: *river.WindowV1, event: river.WindowV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .closed => {
            self.destroy();
        },
        .app_id => |app| {
            self.setIcon(app.app_id);
        },
        .fullscreen_requested => |requested| {
            var output: ?*Output = null;
            if (requested.output) |river_output| {
                output = @ptrCast(@alignCast(river_output.getUserData().?));
            }
            if (output == null) output = self.output;
            self.send(output);
            if (output) |nonull_output| {
                nonull_output.setFullScreen(self);
            }
        },
        .exit_fullscreen_requested => {
            if (self.output) |output| {
                if (output.fullscreen == self) output.setFullScreen(null);
            }
        },
        .dimensions,
        .dimensions_hint,
        .title,
        .parent,
        .decoration_hint,
        .pointer_move_requested,
        .pointer_resize_requested,
        .show_window_menu_requested,
        .maximize_requested,
        .unmaximize_requested,
        .minimize_requested,
        .unreliable_pid,
        => {
            log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
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
        self.river_window.setTiled(.{ .top = true, .bottom = true, .left = true, .right = true });
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

        self.sticky = false;
        if (self.output) |output| {
            if (self.views & (@as(u10, 1) << (output.view - 1)) != 0) {
                self.sticky = true;
            }
        }

        var color = config.border_normal;
        if (self.focused) {
            color = config.border_focused;
            if (self.sticky) color = config.border_sticky;
        }
        self.river_window.setBorders(
            .{ .top = true, .bottom = true, .left = true, .right = true },
            config.border_width,
            color.r,
            color.g,
            color.b,
            color.a,
        );

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

pub fn setWeight(self: *Self, weight: u4) void {
    var new_weight = weight;
    if (new_weight < 1) {
        new_weight = 1;
    } else if (new_weight > 10) {
        new_weight = 10;
    }
    if (new_weight == self.weight) return;
    self.weight = new_weight;
    if (self.output) |output| {
        output.bar.dirty = true;
        if (self.visible) output.dirty = true;
    }
}

pub fn setSticky(self: *Self, sticky: bool) void {
    if (self.sticky == sticky) return;
    if (self.output) |output| {
        self.views ^= @as(u10, 1) << (output.view - 1);
        self.dirty = true;
        output.bar.dirty = true;
        if (!self.focused) output.dirty = true;
    }
}

pub fn send(self: *Self, output: ?*Output) void {
    if (self.output == output) return;
    if (self.output) |old_output| {
        old_output.bar.dirty = true;
        if (self.visible) old_output.dirty = true;
    }
    self.output = output;
    if (self.output) |new_output| {
        new_output.bar.dirty = true;
        if (self.visible) new_output.dirty = true;
    }
}

pub fn swap(self: *Self, another: *Self) void {
    if (self == another) return;
    if (self.output != another.output) return;
    self.link.swapWith(&another.link);
    if (self.output) |output| {
        output.bar.dirty = true;
        if (self.visible or another.visible) output.dirty = true;
    }
}

fn setIcon(self: *Self, id: ?[*:0]const u8) void {
    self.icon = config.app_icon_fallback;
    if (id) |app_id| {
        for (&config.app_icons) |*app_icon| {
            if (std.mem.orderZ(u8, app_icon.id, app_id) == .eq) {
                self.icon = app_icon.icon;
                break;
            }
        }
    }
    if (self.output) |output| output.bar.dirty = true;
}

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("window#{d}", .{self.river_window.getId()});
}
