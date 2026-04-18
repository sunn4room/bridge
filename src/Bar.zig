const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const wp = wayland.client.wp;
const river = wayland.client.river;
const pixman = @import("pixman");
const fcft = @import("fcft");

const Config = @import("Config.zig");
const util = @import("util.zig");
const log = util.log;
const Rect = util.Rect;
const Output = @import("Output.zig");
const Buffer = @import("Buffer.zig");
const Icon = @import("Icon.zig");

pub var bar_background: pixman.Color = undefined;
pub var bar_foreground: pixman.Color = undefined;
pub var bar_selection: pixman.Color = undefined;
pub var bar_theme: pixman.Color = undefined;

const Self = @This();

allocator: std.mem.Allocator,
output: *Output,
wl_surface: *wl.Surface = undefined,
wp_viewport: *wp.Viewport = undefined,
wp_fractional_scale: *wp.FractionalScaleV1 = undefined,
river_shell_surface: *river.ShellSurfaceV1 = undefined,
river_node: *river.NodeV1 = undefined,
config: *const Config = undefined,
scale: i32 = undefined,
width: i32 = undefined,
height: i32 = undefined,
font: ?*fcft.Font = null,
font_base: i32 = undefined,
buffers: wl.list.Head(Buffer, .link) = undefined,
icons: wl.list.Head(Icon, .link) = undefined,
dirty: bool = false,

pub fn create(output: *Output) *Self {
    const self = output.allocator.create(Self) catch unreachable;
    self.* = .{
        .allocator = output.allocator,
        .output = output,
    };
    self.buffers.init();
    self.icons.init();

    self.wl_surface = output.window_manager.wl_compositor.createSurface() catch unreachable;
    self.wp_viewport = output.window_manager.wp_viewporter.getViewport(self.wl_surface) catch unreachable;
    self.wp_fractional_scale = output.window_manager.wp_fractional_scale_manager.getFractionalScale(self.wl_surface) catch unreachable;
    self.wp_fractional_scale.setListener(*Self, wp_fractional_scale_listener, self);
    self.river_shell_surface = output.window_manager.river_window_manager.getShellSurface(self.wl_surface) catch unreachable;
    self.river_node = self.river_shell_surface.getNode() catch unreachable;

    self.scale = 120;

    log.debug("{f} has been created.", .{self});
    return self;
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    if (self.font) |font| font.destroy();

    var buffer_iterator = self.buffers.iterator(.forward);
    while (buffer_iterator.next()) |buffer| buffer.destroy();
    var icon_iterator = self.icons.iterator(.forward);
    while (icon_iterator.next()) |icon| icon.destroy();

    self.river_node.destroy();
    self.river_shell_surface.destroy();
    self.wp_fractional_scale.destroy();
    self.wp_viewport.destroy();
    self.wl_surface.destroy();
    self.allocator.destroy(self);
}

fn wp_fractional_scale_listener(_: *wp.FractionalScaleV1, event: wp.FractionalScaleV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .preferred_scale => |preferred| {
            if (preferred.scale != self.scale) {
                self.scale = @intCast(preferred.scale);
                self.updateFont();
                self.output.window_manager.river_window_manager.manageDirty();
            }
        },
    }
}

pub fn manage(self: *Self) void {
    if (self.dirty) {
        self.dirty = false;

        self.river_node.setPosition(self.output.area.x, self.output.area.y);
        self.river_node.placeBottom();

        const width: i32 = @divFloor(self.output.area.w * self.scale, 120);
        const height: i32 = @intCast(self.font.?.height);
        self.width = width;
        self.height = height;

        const buffer = self.getBuffer();
        const icon_weight = if (self.config.icon_weight) |icon_weight| icon_weight else Config.default.icon_weight.?;
        const icon_view = if (self.config.icon_view) |icon_view| icon_view else Config.default.icon_view.?;

        buffer.prepare(&Self.bar_background);

        var views: u10 = 0;
        var windows_width: i32 = 0;
        var weights_width: i32 = 0;

        {
            var window_iterator = self.output.window_manager.windows.iterator(.forward);
            while (window_iterator.next()) |window| {
                if (window.placed == self.output) {
                    views |= window.views;
                    windows_width += self.getIcon(window.icon).width;
                    if (window.visible) {
                        weights_width += self.getIcon(icon_weight[window.weight - 1]).width;
                    }
                }
            }
        }

        {
            var views_position: i32 = 0;
            var index: u4 = 1;
            while (index <= 10) : (index += 1) {
                const has_window: bool = views & (@as(u10, 1) << (index - 1)) != 0;
                const has_focused: bool = index == self.output.view;
                const icon = icon_view[index - 1];
                const old_position = views_position;
                if (has_focused) {
                    if (has_window) {
                        views_position = buffer.stamp(icon, views_position, &Self.bar_selection, &Self.bar_foreground);
                    } else if (weights_width != 0) {
                        views_position = buffer.stamp(icon, views_position, &Self.bar_selection, &Self.bar_theme);
                    }
                } else {
                    if (has_window) {
                        views_position = buffer.stamp(icon, views_position, null, &Self.bar_foreground);
                    }
                }
                self.output.buttons[index - 1] = self.getButton(old_position, views_position);
            }
        }

        {
            var windows_position: i32 = @divFloor(width - windows_width, 2);
            var weights_position: i32 = width - weights_width;
            var window_iterator = self.output.window_manager.windows.iterator(.forward);
            while (window_iterator.next()) |window| {
                if (window.placed == self.output) {
                    const window_icon = window.icon;
                    const weight_icon = icon_weight[window.weight - 1];
                    const old_windows_position = windows_position;
                    const old_weights_position = weights_position;
                    if (window.focused != 0) {
                        if (window.sticky) {
                            windows_position = buffer.stamp(window_icon, windows_position, &Self.bar_foreground, &Self.bar_selection);
                            weights_position = buffer.stamp(weight_icon, weights_position, &Self.bar_selection, &Self.bar_foreground);
                        } else {
                            windows_position = buffer.stamp(window_icon, windows_position, &Self.bar_theme, &Self.bar_selection);
                            weights_position = buffer.stamp(weight_icon, weights_position, &Self.bar_selection, &Self.bar_theme);
                        }
                    } else {
                        if (window.sticky) {
                            windows_position = buffer.stamp(window_icon, windows_position, &Self.bar_selection, &Self.bar_foreground);
                            weights_position = buffer.stamp(weight_icon, weights_position, null, &Self.bar_foreground);
                        } else {
                            windows_position = buffer.stamp(window_icon, windows_position, null, &Self.bar_foreground);
                        }
                    }
                    window.buttons = .{
                        self.getButton(old_windows_position, windows_position),
                        self.getButton(old_weights_position, weights_position),
                    };
                }
            }
        }

        if (windows_width == 0) {
            const bar_placeholder = if (self.config.bar_placeholder) |bar_placeholder| bar_placeholder else Config.default.bar_placeholder.?;
            const icon_width = self.getIcon(bar_placeholder).width;
            const icon_position: i32 = @divFloor(width - icon_width, 2);
            _ = buffer.stamp(bar_placeholder, icon_position, null, &Self.bar_theme);
        }

        self.wp_viewport.setDestination(self.output.area.w, self.output.window_manager.bar_height);
        self.wl_surface.setBufferScale(1);
        self.wl_surface.attach(buffer.wl_buffer, 0, 0);
        self.wl_surface.damage(0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
        self.wl_surface.commit();
        buffer.busy = true;
    }
}

pub fn getBuffer(self: *Self) *Buffer {
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
    const buffer = Buffer.create(self);
    self.buffers.append(buffer);
    return buffer;
}

pub fn getIcon(self: *Self, key: [*:0]const u8) *Icon {
    var icon_iterator = self.icons.iterator(.forward);
    while (icon_iterator.next()) |icon| {
        if (icon.key == key) return icon;
    }
    const icon = Icon.create(self, key);
    self.icons.append(icon);
    return icon;
}

pub fn getButton(self: *Self, position1: i32, position2: i32) Rect {
    const x: i32 = position1;
    const y: i32 = 0;
    const w: i32 = position2 - position1;
    const h: i32 = self.height;
    return .{
        .x = self.output.area.x + @divFloor(x * 120, self.scale),
        .y = self.output.area.y + @divFloor(y * 120, self.scale),
        .w = @divFloor(w * 120, self.scale),
        .h = @divFloor(h * 120, self.scale),
    };
}

pub fn changeConfig(self: *Self, config: *const Config) void {
    self.config = config;
    self.updateFont();
}

pub fn updateFont(self: *Self) void {
    if (self.font) |font| font.destroy();

    const bar_font = if (self.config.bar_font) |bar_font| bar_font else Config.default.bar_font.?;
    self.font = util.getFont(bar_font, self.scale);
    self.font_base = @divFloor(self.font.?.height + self.font.?.descent + self.font.?.ascent, 2);
    if (self.font.?.descent > 0) self.font_base -= self.font.?.descent;

    var icon_iterator = self.icons.iterator(.forward);
    while (icon_iterator.next()) |icon| icon.destroy();

    self.dirty = true;
}

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("bar#{d}", .{self.output.river_output.getId()});
}
