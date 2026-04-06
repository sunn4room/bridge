const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const config = @import("config.zig");
const util = @import("util.zig");
const log = util.log;
const Rect = util.Rect;
const WindowManager = @import("WindowManager.zig");
const Seat = @import("Seat.zig");
const Window = @import("Window.zig");

const Self = @This();

allocator: std.mem.Allocator,
window_manager: *WindowManager,
river_output: *river.OutputV1,
river_layer_shell_output: *river.LayerShellOutputV1,
link: wl.list.Link = undefined,
area: ?Rect = null,
view: u4 = 1,
buttons: [10]?Rect = .{null} ** 10,
fullscreen: ?*Window = null,
layout_updated: bool = false,

pub fn create(window_manager: *WindowManager, river_output: *river.OutputV1) *Self {
    const self = window_manager.allocator.create(Self) catch unreachable;
    self.* = .{
        .allocator = window_manager.allocator,
        .window_manager = window_manager,
        .river_output = river_output,
        .river_layer_shell_output = window_manager.river_layer_shell.getOutput(river_output) catch unreachable,
    };

    self.river_output.setListener(*Self, river_output_listener, self);
    self.river_layer_shell_output.setListener(*Self, river_layer_shell_output_listener, self);
    self.link.init();

    log.debug("{f} has been created.", .{self});
    return self;
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    self.link.remove();
    self.river_output.destroy();
    self.river_layer_shell_output.destroy();
    self.allocator.destroy(self);
}

fn river_output_listener(_: *river.OutputV1, event: river.OutputV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .removed => {
            self.destroy();
        },
        .wl_output,
        .dimensions,
        .position,
        => {
            log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
}

fn river_layer_shell_output_listener(_: *river.LayerShellOutputV1, event: river.LayerShellOutputV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .non_exclusive_area => |area| {
            self.area = .{
                .x = area.x,
                .y = area.y,
                .w = area.width,
                .h = area.height,
            };
            self.layout_updated = true;
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
        if (link == &self.window_manager.outputs.link) continue;
        break @fieldParentPtr("link", link);
    };
}

pub fn manage(self: *Self) void {
    if (self.area) |area| {
        if (self.layout_updated) {
            self.layout_updated = false;

            var total_weight: i32 = 0;
            var window_iterator = self.window_manager.windows.iterator(.forward);
            while (window_iterator.next()) |window| {
                if (window.placed == self and window.visible and !window.floating) {
                    total_weight += window.weight;
                }
            }

            if (total_weight != 0) {
                var occupied_weight: i32 = 0;
                window_iterator = self.window_manager.windows.iterator(.forward);
                while (window_iterator.next()) |window| {
                    if (window.placed == self and window.visible and !window.floating) {
                        var window_area: Rect = undefined;
                        const gap: i32 = config.layout_gap;
                        const total_width: i32 = area.w - gap;
                        const occupied_width: i32 = @divFloor(total_width * occupied_weight, total_weight);
                        const window_width: i32 = @divFloor(total_width * window.weight, total_weight);
                        window_area.x = gap + occupied_width + config.border_width;
                        window_area.y = self.window_manager.bar_height + gap + config.border_width;
                        window_area.w = window_width - gap - 2 * config.border_width;
                        window_area.h = area.h - self.window_manager.bar_height - 2 * gap - 2 * config.border_width;
                        window.river_node.setPosition(window_area.x, window_area.y);
                        window.river_window.proposeDimensions(window_area.w, window_area.h);
                        window.area = window_area;
                        log.debug(
                            "{f} layout {f}: {}, {}, {}, {}",
                            .{
                                self,
                                window,
                                window_area.x,
                                window_area.y,
                                window_area.w,
                                window_area.h,
                            },
                        );
                        occupied_weight += window.weight;
                    }
                }
            }
        }
    }
}

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("output#{d}", .{self.river_output.getId()});
}
