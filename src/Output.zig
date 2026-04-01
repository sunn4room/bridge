const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const config = @import("config.zig");
const util = @import("util.zig");
const log = util.log;
const WindowManager = @import("WindowManager.zig");
const Window = @import("Window.zig");

const Self = @This();

window_manager: *WindowManager,
river_output: *river.OutputV1,
river_layer_shell_output: *river.LayerShellOutputV1,
link: wl.list.Link = undefined,
dirty: bool = false,
x: ?i32 = null,
y: ?i32 = null,
width: ?i32 = null,
height: ?i32 = null,

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
    log.debug("{f} has been created.", .{self});
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});
    self.link.remove();
    const fallback = self.window_manager.outputs.first();
    var window_iterator = self.window_manager.windows.iterator(.forward);
    while (window_iterator.next()) |window| if (window.output == self) window.send(fallback);
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
            self.x = area.x;
            self.y = area.y;
            self.width = area.width;
            self.height = area.height;
            self.dirty = true;
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
    if (self.x == null or self.y == null or self.width == null or self.height == null) return;

    if (self.dirty) {
        defer log.debug("{f} has updated state.", .{self});

        _ = self.layout(&self.window_manager.windows.link, 0);
        self.dirty = false;
    }
}

fn layout(self: *Self, original_link: *wl.list.Link, occupied: i32) i32 {
    var link = original_link;
    while (link.next.? != &self.window_manager.windows.link) : (link = link.next.?) {
        const each_window: *Window = @fieldParentPtr("link", link.next.?);
        if (each_window.output == self and each_window.visible) {
            const weight: i32 = each_window.weight;
            const needed: i32 = self.layout(&each_window.link, occupied + weight);
            const total: i32 = occupied + weight + needed;
            const gap: i32 = config.layout_gap;
            const total_width: i32 = self.width.? - gap;
            const occupied_width: i32 = @divFloor(occupied * total_width, total);
            const weight_width: i32 = @divFloor(weight * total_width, total);
            each_window.node.setPosition(gap + occupied_width + config.border_width, gap + config.border_width);
            each_window.river_window.proposeDimensions(weight_width - gap - 2 * config.border_width, self.height.? - 2 * gap - 2 * config.border_width);
            return weight + needed;
        }
    }
    return 0;
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("output#{d}", .{self.river_output.getId()});
}
