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
const Seat = @import("Seat.zig");

const Self = @This();

allocator: std.mem.Allocator,
window_manager: *WindowManager,
river_window: *river.WindowV1,
river_node: *river.NodeV1,
link: wl.list.Link = undefined,
flink: wl.list.Link = undefined,
placed: ?*Output = null,
area: ?Rect = null,
new: bool = true,
close: bool = false,
weight: u4 = 5,
views: u10 = 0,
sticky: bool = false,
focused: u32 = 0,
border_updated: bool = false,
border: util.Color = config.border_normal,
visible_updated: bool = false,
visible: bool = false,
floating_updated: bool = false,
floating: bool = false,
fullscreen_updated: bool = false,
fullscreen: bool = false,

pub fn create(window_manager: *WindowManager, river_window: *river.WindowV1) *Self {
    const self = window_manager.allocator.create(Self) catch unreachable;
    self.* = .{
        .allocator = window_manager.allocator,
        .window_manager = window_manager,
        .river_window = river_window,
        .river_node = river_window.getNode() catch unreachable,
    };

    river_window.setListener(*Self, river_window_listener, self);
    self.link.init();
    self.flink.init();

    log.debug("{f} has been created.", .{self});
    return self;
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    self.flink.remove();
    self.link.remove();
    self.river_node.destroy();
    self.river_window.destroy();
    self.allocator.destroy(self);
}

fn river_window_listener(_: *river.WindowV1, event: river.WindowV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .closed => {
            self.destroy();
        },
        .fullscreen_requested => {},
        .exit_fullscreen_requested => {},
        .pointer_move_requested, .pointer_resize_requested, .dimensions, .dimensions_hint, .app_id => {},
        .title,
        .parent,
        .decoration_hint,
        .show_window_menu_requested,
        .maximize_requested,
        .unmaximize_requested,
        .minimize_requested,
        .unreliable_pid,
        .presentation_hint,
        .identifier,
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

pub fn fiterate(self: *Self, dir: wl.list.Direction) *Self {
    var flink: *wl.list.Link = &self.flink;
    return while (true) {
        flink = switch (dir) {
            .forward => flink.next.?,
            .reverse => flink.prev.?,
        };
        if (flink == &self.window_manager.fwindows.link) continue;
        break @fieldParentPtr("flink", flink);
    };
}

pub fn manage(self: *Self) void {
    if (self.new) {
        self.new = false;
        self.river_window.useSsd();
        self.river_window.setTiled(.{ .top = true, .bottom = true, .left = true, .right = true });
    }

    if (self.close) {
        self.close = false;
        self.river_window.close();
    }

    if (self.border_updated) {
        self.border_updated = false;
        self.river_window.setBorders(.{ .top = true, .bottom = true, .left = true, .right = true }, config.border_width, self.border.r, self.border.g, self.border.b, self.border.a);
    }

    if (self.visible_updated) {
        self.visible_updated = false;

        if (self.visible) {
            self.river_window.show();
        } else {
            self.river_window.hide();
        }
        log.debug("{f} has been {s}.", .{ self, if (self.visible) "visible" else "not visible" });
    }

    if (self.floating_updated) {
        self.floating_updated = false;

        if (self.floating) {
            self.river_node.placeTop();
        } else {
            self.river_node.placeBottom();
        }
        log.debug("{f} has been {s}.", .{ self, if (self.floating) "floating" else "not floating" });
    }

    if (self.fullscreen_updated) {
        self.fullscreen_updated = false;

        if (self.fullscreen) {
            self.river_window.informFullscreen();
            self.river_window.fullscreen(self.placed.?.river_output);
        } else {
            self.river_window.informNotFullscreen();
            self.river_window.exitFullscreen();
        }
        log.debug("{f} has been {s}.", .{ self, if (self.fullscreen) "fullscreen" else "not fullscreen" });
    }
}

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("window#{d}", .{self.river_window.getId()});
}
