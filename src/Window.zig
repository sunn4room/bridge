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
area: Rect = undefined,
buttons: [2]Rect = undefined,
icon: [*:0]const u8 = config.app_icon_fallback,
new: bool = true,
close: bool = false,
weight: u4 = 5,
views: u10 = 0,
sticky: bool = false,
focused: u32 = 0,
border_updated: bool = false,
border: *const util.Color = &config.border_normal,
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
            self.place(null);
            var fallback: ?*Self = null;
            const last_focused_window = self.fiterate(.reverse);
            if (last_focused_window != self) fallback = last_focused_window;

            var seat_iterator = self.window_manager.seats.iterator(.forward);
            while (seat_iterator.next()) |seat| {
                seat.cancel(self);
                if (seat.focused == self) {
                    seat.focus(fallback);
                }
            }
            self.destroy();
        },
        .fullscreen_requested => |data| {
            var output: ?*Output = self.placed;
            if (data.output) |river_output| {
                output = @ptrCast(@alignCast(river_output.getUserData().?));
            }
            self.place(output);
            self.switchFullscreen(true);
        },
        .exit_fullscreen_requested => {
            self.switchFullscreen(false);
        },
        .app_id => |data| {
            self.changeIcon(data.app_id);
        },
        .pointer_move_requested => |data| {
            if (data.seat) |river_seat| {
                const seat: *Seat = @ptrCast(@alignCast(river_seat.getUserData().?));
                seat.move(self);
            }
        },
        .pointer_resize_requested => |data| {
            if (data.seat) |river_seat| {
                const seat: *Seat = @ptrCast(@alignCast(river_seat.getUserData().?));
                seat.resize(self, data.edges);
            }
        },
        .dimensions,
        .dimensions_hint,
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
            self.river_node.setPosition(self.area.x, self.area.y);
            self.river_window.proposeDimensions(self.area.w, self.area.h);
        }
        log.debug("{f} has been {s}.", .{ self, if (self.fullscreen) "fullscreen" else "not fullscreen" });
    }
}

pub fn place(self: *Self, output: ?*Output) void {
    if (output != self.placed) {
        self.switchFloating(false);
        self.switchFullscreen(false);

        if (self.placed) |old_output| {
            old_output.dirty = true;
            old_output.bar.dirty = true;
        }
        self.placed = output;
        if (self.placed) |new_output| {
            new_output.dirty = true;
            new_output.bar.dirty = true;
        }

        self.update_sticky();
        self.update_visible();
    }
}

pub fn focus(self: *Self, focused: bool) void {
    var updated: bool = false;
    if (focused) {
        self.focused += 1;
        self.flink.remove();
        self.window_manager.fwindows.append(self);
        if (self.focused == 1) updated = true;
        if (self.floating) self.floating_updated = true;
    } else {
        self.focused -= 1;
        if (self.focused == 0) updated = true;
    }

    if (updated) {
        if (self.placed) |output| output.bar.dirty = true;
        self.update_border();
        self.update_visible();
    }
}

pub fn switchSticky(self: *Self, sticky_or_null: ?bool) void {
    if (self.placed) |output| {
        const sticky = if (sticky_or_null) |nonull_sticky| nonull_sticky else !self.sticky;
        if (self.sticky == sticky) return;
        self.views ^= @as(u10, 1) << (output.view - 1);
        self.update_sticky();
    }
}

pub fn update_sticky(self: *Self) void {
    var sticky: bool = false;
    if (self.placed) |output| {
        sticky = self.views & (@as(u10, 1) << (output.view - 1)) != 0;
    }

    if (sticky != self.sticky) {
        self.sticky = sticky;
        if (self.placed) |output| output.bar.dirty = true;
        self.update_border();
        self.update_visible();
    }
}

pub fn update_border(self: *Self) void {
    var border = &config.border_normal;
    if (self.focused != 0) {
        border = &config.border_focused;
        if (self.sticky) {
            border = &config.border_sticky;
        }
    }

    if (border != self.border) {
        self.border = border;
        self.border_updated = true;
    }
}

pub fn update_visible(self: *Self) void {
    const visible: bool = self.placed != null and (self.focused != 0 or self.sticky);

    if (visible != self.visible) {
        self.visible = visible;
        self.visible_updated = true;
        if (self.placed) |output| {
            output.bar.dirty = true;
            if (!self.floating) output.dirty = true;
        }
    }
}

pub fn changeWeight(self: *Self, weight: u4) void {
    if (weight != self.weight) {
        self.weight = weight;
        if (self.placed) |output| {
            output.bar.dirty = true;
            if (self.visible and !self.floating) output.dirty = true;
        }
    }
}

pub fn switchFullscreen(self: *Self, fullscreen_or_null: ?bool) void {
    const fullscreen = if (fullscreen_or_null) |nonull_fullscreen| nonull_fullscreen else !self.fullscreen;
    if (fullscreen == self.fullscreen) return;

    self.fullscreen = fullscreen;
    self.fullscreen_updated = true;

    if (self.placed) |output| {
        if (self.fullscreen) {
            if (output.fullscreen) |old_window| {
                old_window.switchFullscreen(false);
            }
            output.fullscreen = self;
        } else {
            output.fullscreen = null;
        }
    }
}

pub fn switchFloating(self: *Self, floating_or_null: ?bool) void {
    const floating = if (floating_or_null) |nonull_floating| nonull_floating else !self.floating;
    if (floating == self.floating) return;

    self.floating = floating;
    self.floating_updated = true;
    if (self.placed) |output| output.dirty = true;
}

pub fn changeIcon(self: *Self, id: ?[*:0]const u8) void {
    var icon = config.app_icon_fallback;
    if (id) |app_id| {
        for (&config.app_icons) |*app_icon| {
            if (std.mem.orderZ(u8, app_icon.id, app_id) == .eq) {
                icon = app_icon.icon;
                break;
            }
        }
    }
    if (icon != self.icon) {
        self.icon = icon;
        if (self.placed) |output| output.bar.dirty = true;
    }
}

pub fn swap(self: *Self, other: *Self) void {
    if (self == other) return;

    self.link.swapWith(&other.link);
    if (self.placed) |output| {
        output.dirty = true;
        output.bar.dirty = true;
    }
    if (other.placed) |output| {
        output.dirty = true;
        output.bar.dirty = true;
    }
}

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("window#{d}", .{self.river_window.getId()});
}
