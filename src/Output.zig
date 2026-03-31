const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const util = @import("util.zig");
const config = @import("config.zig");
const WindowManager = @import("WindowManager.zig");
const Window = @import("Window.zig");

const Self = @This();

handle: *river.OutputV1,
layer_shell_output: *river.LayerShellOutputV1,
window_manager: *WindowManager,
link: wl.list.Link = undefined,
dirty: bool = false,
x: ?i32 = null,
y: ?i32 = null,
width: ?i32 = null,
height: ?i32 = null,

fn river_output_listener(
    _: *river.OutputV1,
    event: river.OutputV1.Event,
    self: *Self,
) void {
    util.log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .removed => {
            self.destroy();
        },
        else => {
            util.log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
}

fn river_layer_shell_output_listener(
    _: *river.LayerShellOutputV1,
    event: river.LayerShellOutputV1.Event,
    self: *Self,
) void {
    util.log.debug("{f} received {s} event.", .{ self, @tagName(event) });
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

pub fn inject(handle: *river.OutputV1, window_manager: *WindowManager) void {
    const output = std.heap.c_allocator.create(Self) catch unreachable;
    handle.setListener(*Self, river_output_listener, output);
    const layer_shell_output = window_manager.bridge.layer_shell_manager.?.handle.getOutput(handle) catch unreachable;
    layer_shell_output.setListener(*Self, river_layer_shell_output_listener, output);
    output.* = .{
        .handle = handle,
        .layer_shell_output = layer_shell_output,
        .window_manager = window_manager,
    };
    window_manager.outputs.append(output);
    var window_iterator = window_manager.windows.iterator(.forward);
    while (window_iterator.next()) |window| if (window.output == null) window.send(output);
    util.log.debug("{f} has been created.", .{output});
}

pub fn destroy(self: *Self) void {
    util.log.debug("{f} is about to be destroyed.", .{self});
    self.link.remove();
    const fallback_output = self.window_manager.outputs.first();
    var window_iterator = self.window_manager.windows.iterator(.forward);
    while (window_iterator.next()) |window| if (window.output == self) window.send(fallback_output);
    self.handle.destroy();
    self.layer_shell_output.destroy();
    std.heap.c_allocator.destroy(self);
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

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("output#{d}", .{self.handle.getId()});
}

pub fn manage(self: *Self) void {
    if (self.x == null or self.y == null or self.width == null or self.height == null) return;

    if (self.dirty) {
        defer util.log.debug("{f} has updated state.", .{self});

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
            each_window.handle.proposeDimensions(weight_width - gap - 2 * config.border_width, self.height.? - 2 * gap - 2 * config.border_width);
            return weight + needed;
        }
    }
    return 0;
}
