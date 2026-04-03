const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const wp = wayland.client.wp;
const river = wayland.client.river;
const pixman = @import("pixman");
const fcft = @import("fcft");

const config = @import("config.zig");
const util = @import("util.zig");
const log = util.log;
const Rect = util.Rect;
const Output = @import("Output.zig");
const Buffer = @import("Buffer.zig");
const IconRun = @import("IconRun.zig");

const Self = @This();

output: *Output,
wl_surface: *wl.Surface = undefined,
wp_viewport: *wp.Viewport = undefined,
wp_fractional_scale: *wp.FractionalScaleV1 = undefined,
river_shell_surface: *river.ShellSurfaceV1 = undefined,
river_node: *river.NodeV1 = undefined,
dirty: bool = false,
scale: u31 = undefined,
width: u31 = undefined,
height: u31 = undefined,
font: *fcft.Font = undefined,
font_base: i32 = undefined,
buffers: wl.list.Head(Buffer, .link) = undefined,
icon_runs: wl.list.Head(IconRun, .link) = undefined,

pub fn bind(output: *Output) void {
    const self = std.heap.c_allocator.create(Self) catch unreachable;
    self.* = .{ .output = output };

    self.wl_surface = output.window_manager.wl_compositor.createSurface() catch unreachable;
    self.wp_viewport = output.window_manager.wp_viewporter.getViewport(self.wl_surface) catch unreachable;
    self.wp_fractional_scale = output.window_manager.wp_fractional_scale_manager.getFractionalScale(self.wl_surface) catch unreachable;
    self.wp_fractional_scale.setListener(*Self, wp_fractional_scale_listener, self);
    self.river_shell_surface = output.window_manager.river_window_manager.getShellSurface(self.wl_surface) catch unreachable;
    self.river_node = self.river_shell_surface.getNode() catch unreachable;

    output.bar = self;

    self.buffers.init();
    self.icon_runs.init();

    self.scale = 120;
    self.font = util.getFont(self.scale);
    self.font_base = @divFloor(self.font.height + self.font.descent + self.font.ascent, 2);
    if (self.font.descent > 0) self.font_base -= self.font.descent;

    log.debug("{f} has been created.", .{self});
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    self.font.destroy();

    var buffer_iterator = self.buffers.iterator(.forward);
    while (buffer_iterator.next()) |buffer| buffer.destroy();
    var icon_run_iterator = self.icon_runs.iterator(.forward);
    while (icon_run_iterator.next()) |icon_run| icon_run.destroy();

    self.river_node.destroy();
    self.river_shell_surface.destroy();
    self.wp_fractional_scale.destroy();
    self.wp_viewport.destroy();
    self.wl_surface.destroy();

    std.heap.c_allocator.destroy(self);
}

fn wp_fractional_scale_listener(_: *wp.FractionalScaleV1, event: wp.FractionalScaleV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .preferred_scale => |preferred| {
            if (preferred.scale != self.scale) {
                self.scale = @intCast(preferred.scale);

                self.font.destroy();
                self.font = util.getFont(self.scale);
                self.font_base = @divFloor(self.font.height + self.font.descent + self.font.ascent, 2);
                if (self.font.descent > 0) self.font_base -= self.font.descent;

                var icon_run_iterator = self.icon_runs.iterator(.forward);
                while (icon_run_iterator.next()) |icon_run| icon_run.destroy();

                self.dirty = true;
                self.output.window_manager.river_window_manager.manageDirty();
            }
        },
    }
}

pub fn manage(self: *Self) void {
    if (self.dirty) {
        defer log.debug("{f} has updated state.", .{self});

        self.river_node.setPosition(self.output.area.?.x, self.output.area.?.y);
        self.river_node.placeTop();

        const width: u31 = @divFloor(self.output.area.?.w * self.scale, 120);
        const height: u31 = @intCast(self.font.height);
        self.width = width;
        self.height = height;

        const buffer = self.getBuffer();

        buffer.prepare();

        var views: u10 = 0;
        var windows_width: u31 = 0;
        var weights_width: u31 = 0;

        {
            var window_iterator = self.output.window_manager.windows.iterator(.forward);
            while (window_iterator.next()) |window| {
                if (window.output == self.output) {
                    views |= window.views;
                    windows_width += self.getIconRun(window.icon).width;
                    if (window.visible) {
                        weights_width += self.getIconRun(config.box_icons[window.weight]).width;
                    }
                }
            }
        }

        {
            var views_position: u31 = 0;
            var index: u4 = 1;
            while (index <= 10) : (index += 1) {
                const has_window: bool = views & (@as(u10, 1) << (index - 1)) != 0;
                const has_focused: bool = index == self.output.view;
                const icon_run = self.getIconRun(config.boxes_icons[index]);
                const old_position = views_position;
                if (has_focused) {
                    if (has_window) {
                        views_position = buffer.stamp(icon_run, views_position, &config.bar_selection, &config.bar_foreground);
                    } else {
                        views_position = buffer.stamp(icon_run, views_position, &config.bar_selection, &config.bar_theme);
                    }
                } else {
                    if (has_window) {
                        views_position = buffer.stamp(icon_run, views_position, null, &config.bar_foreground);
                    }
                }
                self.output.buttons[index - 1] = self.getRect(old_position, views_position);
            }
        }

        {
            var windows_position: u31 = @divFloor(width - windows_width, 2);
            var weights_position: u31 = width - weights_width;
            var window_iterator = self.output.window_manager.windows.iterator(.forward);
            while (window_iterator.next()) |window| {
                if (window.output == self.output) {
                    const window_icon_run = self.getIconRun(window.icon);
                    const weight_icon_run = self.getIconRun(config.box_icons[window.weight]);
                    const old_windows_position = windows_position;
                    const old_weights_position = weights_position;
                    if (window.focused) {
                        if (window.sticky) {
                            windows_position = buffer.stamp(window_icon_run, windows_position, &config.bar_selection, &config.bar_foreground);
                            weights_position = buffer.stamp(weight_icon_run, weights_position, &config.bar_selection, &config.bar_foreground);
                        } else {
                            windows_position = buffer.stamp(window_icon_run, windows_position, &config.bar_selection, &config.bar_theme);
                            weights_position = buffer.stamp(weight_icon_run, weights_position, &config.bar_selection, &config.bar_theme);
                        }
                    } else {
                        if (window.sticky) {
                            windows_position = buffer.stamp(window_icon_run, windows_position, null, &config.bar_foreground);
                            weights_position = buffer.stamp(weight_icon_run, weights_position, null, &config.bar_foreground);
                        } else {
                            windows_position = buffer.stamp(window_icon_run, windows_position, null, &config.bar_selection);
                        }
                    }
                    window.buttons = .{
                        self.getRect(old_windows_position, windows_position),
                        self.getRect(old_weights_position, weights_position),
                    };
                }
            }
            if (weights_width == 0) {
                const icon_run = self.getIconRun(config.box_icons[0]);
                _ = buffer.stamp(icon_run, width - icon_run.width, &config.bar_selection, &config.bar_theme);
            }
        }

        self.wp_viewport.setDestination(self.output.area.?.w, self.output.window_manager.bar_height);
        self.wl_surface.setBufferScale(1);
        self.wl_surface.attach(buffer.wl_buffer, 0, 0);
        self.wl_surface.damage(0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
        self.wl_surface.commit();
        buffer.busy = true;

        self.dirty = false;
    }
}

fn getBuffer(self: *Self) *Buffer {
    var buffer_iterator = self.buffers.iterator(.reverse);
    while (buffer_iterator.next()) |buffer| {
        if (!buffer.busy) {
            if (buffer.height == self.height and buffer.width == self.width) {
                log.debug("{f} reuses {f}.", .{ self, buffer });
                return buffer;
            } else {
                buffer.destroy();
            }
        } else {
            break;
        }
    }
    Buffer.bind(self);
    return self.buffers.last().?;
}

fn getIconRun(self: *Self, icon: [*:0]const u8) *IconRun {
    var icon_run_iterator = self.icon_runs.iterator(.forward);
    while (icon_run_iterator.next()) |icon_run| {
        if (icon_run.icon == icon) return icon_run;
    }
    IconRun.bind(self, icon);
    return self.icon_runs.last().?;
}

fn getRect(self: *Self, position1: u31, position2: u31) ?Rect {
    if (position1 == position2) return null;
    const x: i32 = position1;
    const y: i32 = 0;
    const w: u31 = position2 - position1;
    const h: u31 = self.height;
    return .{
        .x = self.output.area.?.x + @divFloor(x * 120, self.scale),
        .y = self.output.area.?.y + @divFloor(y * 120, self.scale),
        .w = @divFloor(w * 120, self.scale),
        .h = @divFloor(h * 120, self.scale),
    };
}

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("bar#{d}", .{self.output.river_output.getId()});
}
