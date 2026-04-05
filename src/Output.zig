const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const config = @import("config.zig");
const util = @import("util.zig");
const log = util.log;
const Rect = util.Rect;
const WindowManager = @import("WindowManager.zig");
const Window = @import("Window.zig");
const Bar = @import("Bar.zig");

const Self = @This();

window_manager: *WindowManager,
river_output: *river.OutputV1,
river_layer_shell_output: *river.LayerShellOutputV1,
link: wl.list.Link = undefined,
dirty: bool = false,
area: ?Rect = null,
view: u4 = 1,
bar: *Bar = undefined,
buttons: [10]?Rect = .{null} ** 10,
fullscreen: ?*Window = null,

pub fn bind(window_manager: *WindowManager, river_output: *river.OutputV1) void {
    const self = std.heap.c_allocator.create(Self) catch unreachable;
    river_output.setListener(*Self, river_output_listener, self);

    const river_layer_shell_output = window_manager.river_layer_shell.getOutput(river_output) catch unreachable;
    river_layer_shell_output.setListener(*Self, river_layer_shell_output_listener, self);

    self.* = .{
        .window_manager = window_manager,
        .river_output = river_output,
        .river_layer_shell_output = river_layer_shell_output,
    };

    self.link.init();
    window_manager.outputs.append(self);

    var window_iterator = window_manager.windows.iterator(.forward);
    while (window_iterator.next()) |window| if (window.output == null) window.send(self);

    Bar.bind(self);

    log.debug("{f} has been created.", .{self});
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    self.bar.destroy();

    self.link.remove();

    var fallback: ?*Self = null;
    {
        var window_iterator = self.window_manager.windows.iterator(.reverse);
        while (window_iterator.next()) |window| {
            if (window.output != self) {
                fallback = window.output;
                break;
            }
        }
    }
    {
        var window_iterator = self.window_manager.windows.iterator(.forward);
        while (window_iterator.next()) |window| {
            if (window.output == self) window.send(fallback);
        }
    }

    self.river_output.destroy();
    self.river_layer_shell_output.destroy();
    std.heap.c_allocator.destroy(self);
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
                .w = @intCast(area.width),
                .h = @intCast(area.height),
            };
            self.dirty = true;
            self.bar.dirty = true;
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
    if (self.area == null) return;

    self.bar.manage();

    if (self.dirty) {
        defer log.debug("{f} has updated state.", .{self});

        if (self.fullscreen) |fullscreen| {
            var window_iterator = self.window_manager.windows.iterator(.forward);
            while (window_iterator.next()) |window| {
                if (window == fullscreen) {
                    window.river_window.informFullscreen();
                    window.river_window.fullscreen(self.river_output);
                    window.river_node.placeTop();
                } else {
                    window.river_window.informNotFullscreen();
                    window.river_window.exitFullscreen();
                    window.river_node.placeBottom();
                }
            }
        } else {
            var total_weight: i32 = 0;
            var window_iterator = self.window_manager.windows.iterator(.forward);
            while (window_iterator.next()) |window| {
                if (window.output == self and window.visible) {
                    if (window.floating) {
                        if (window.focused) {
                            window.river_node.placeTop();
                        }
                    } else {
                        total_weight += window.weight;
                    }
                }
            }

            if (total_weight != 0) {
                var occupied_weight: i32 = 0;
                window_iterator = self.window_manager.windows.iterator(.forward);
                while (window_iterator.next()) |window| {
                    if (window.output == self and window.visible and !window.floating) {
                        window.river_window.informNotFullscreen();
                        window.river_window.exitFullscreen();
                        const gap: i32 = config.layout_gap;
                        const total_width: i32 = self.area.?.w - gap;
                        const occupied_width: i32 = @divFloor(total_width * occupied_weight, total_weight);
                        const window_width: i32 = @divFloor(total_width * window.weight, total_weight);
                        const x: i32 = gap + occupied_width + config.border_width;
                        const y: i32 = self.window_manager.bar_height + gap + config.border_width;
                        const w: i32 = window_width - gap - 2 * config.border_width;
                        const h: i32 = self.area.?.h - self.window_manager.bar_height - 2 * gap - 2 * config.border_width;
                        window.river_node.placeBottom();
                        window.river_node.setPosition(x, y);
                        window.river_window.proposeDimensions(w, h);
                        window.area = .{
                            .x = x,
                            .y = y,
                            .w = @intCast(w),
                            .h = @intCast(h),
                        };
                        occupied_weight += window.weight;
                    }
                }
            }
        }
        self.dirty = false;
    }
}

pub fn setView(self: *Self, view: u4) void {
    var new_view = view;
    if (new_view < 1) {
        new_view = 1;
    } else if (new_view > 10) {
        new_view = 10;
    }

    if (new_view == self.view) return;
    self.view = new_view;

    self.dirty = true;
    self.bar.dirty = true;
    var window_iterator = self.window_manager.windows.iterator(.forward);
    while (window_iterator.next()) |window| {
        if (window.output == self) window.dirty = true;
    }
}

pub fn setFullScreen(self: *Self, window: ?*Window) void {
    if (self.fullscreen == window) return;
    if (window) |nonull_window| nonull_window.send(self);
    self.fullscreen = window;
    self.dirty = true;
}

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("output#{d}", .{self.river_output.getId()});
}
