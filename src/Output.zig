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
const Bar = @import("Bar.zig");

const Self = @This();

allocator: std.mem.Allocator,
window_manager: *WindowManager,
river_output: *river.OutputV1,
river_layer_shell_output: *river.LayerShellOutputV1,
link: wl.list.Link = undefined,
area: Rect = undefined,
view: u4 = 1,
buttons: [10]Rect = undefined,
fullscreen: ?*Window = null,
dirty: bool = false,
bar: *Bar = undefined,

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

    self.bar = Bar.create(self);

    log.debug("{f} has been created.", .{self});
    return self;
}

pub fn pre(self: *Self) void {
    var window_iterator = self.window_manager.windows.iterator(.forward);
    while (window_iterator.next()) |window| if (window.placed == null) window.place(self);
}

pub fn post(self: *Self) void {
    var fallback: ?*Self = null;
    const prev_output = self.iterate(.reverse);
    if (prev_output != self) fallback = prev_output;
    var window_iterator = self.window_manager.windows.iterator(.forward);
    while (window_iterator.next()) |window| {
        if (window.placed == self) window.place(fallback);
    }
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    self.bar.destroy();
    self.link.remove();
    self.river_output.destroy();
    self.river_layer_shell_output.destroy();
    self.allocator.destroy(self);
}

fn river_output_listener(_: *river.OutputV1, event: river.OutputV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .removed => {
            self.post();
            self.destroy();
        },
        else => {
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
            self.dirty = true;
            self.bar.dirty = true;
            if (self.link.next == &self.link) {
                self.window_manager.outputs.append(self);
                self.pre();
            }
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
    self.bar.manage();

    if (self.dirty) {
        self.dirty = false;

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
                    var area: Rect = undefined;
                    const gap: i32 = config.layout_gap;
                    const total_width: i32 = self.area.w - gap;
                    const occupied_width: i32 = @divFloor(total_width * occupied_weight, total_weight);
                    const window_width: i32 = @divFloor(total_width * window.weight, total_weight);
                    area.x = self.area.x + gap + occupied_width + config.border_width;
                    area.y = self.area.y + self.window_manager.bar_height + gap + config.border_width;
                    area.w = window_width - gap - 2 * config.border_width;
                    area.h = self.area.h - self.window_manager.bar_height - 2 * gap - 2 * config.border_width;
                    window.river_node.setPosition(area.x, area.y);
                    window.river_window.proposeDimensions(area.w, area.h);
                    window.area = area;
                    log.info(
                        "{f} layout {f}: {}, {}, {}, {}",
                        .{
                            self,
                            window,
                            area.x,
                            area.y,
                            area.w,
                            area.h,
                        },
                    );
                    occupied_weight += window.weight;
                }
            }
        }
    }
}

pub fn changeView(self: *Self, view: u4) ?*Window {
    var sticky_window_or_null: ?*Window = null;

    if (view != self.view) {
        self.view = view;
        self.bar.dirty = true;

        var window_iterator = self.window_manager.windows.iterator(.forward);
        while (window_iterator.next()) |window| {
            if (window.placed == self) {
                window.updateSticky();
                if (window.sticky and sticky_window_or_null == null) {
                    sticky_window_or_null = window;
                }
            }
        }
    }
    return sticky_window_or_null;
}

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("output#{d}", .{self.river_output.getId()});
}
