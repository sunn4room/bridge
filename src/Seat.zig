const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;
const Modifiers = river.SeatV1.Modifiers;
const xkbcommon = @import("xkbcommon");
const Keysym = xkbcommon.Keysym;

const util = @import("util.zig");
const Binding = util.Binding;
const Action = util.Action;
const config = @import("config.zig");
const WindowManager = @import("WindowManager.zig");
const XkbBindingManager = @import("XkbBindingManager.zig");
const XkbBinding = @import("XkbBinding.zig");
const PointerBinding = @import("PointerBinding.zig");
const Output = @import("Output.zig");
const Window = @import("Window.zig");

const Self = @This();

handle: *river.SeatV1,
window_manager: *WindowManager,

link: wl.list.Link = undefined,
new: bool = true,
xkb_bindings: wl.list.Head(XkbBinding, .link) = undefined,
pointer_bindings: wl.list.Head(PointerBinding, .link) = undefined,
action: Action = .nop,
enabled: bool = false,
window: ?*Window = null,

fn river_seat_listener(
    _: *river.SeatV1,
    event: river.SeatV1.Event,
    self: *Self,
) void {
    switch (event) {
        .removed => self.destroy(),
        else => util.log.debug("{f} ignored {s} event.", .{ self, @tagName(event) }),
    }
}

pub fn inject(handle: *river.SeatV1, window_manager: *WindowManager) void {
    const seat = std.heap.c_allocator.create(Self) catch unreachable;
    seat.* = .{ .handle = handle, .window_manager = window_manager };
    handle.setListener(*Self, river_seat_listener, seat);
    seat.xkb_bindings.init();
    seat.pointer_bindings.init();
    for (config.bindings) |binding| {
        switch (binding.trigger) {
            .keysym => |keysym| {
                const xkb_binding_manager = window_manager.bridge.xkb_binding_manager;
                const xkb_binding_handle = xkb_binding_manager.handle.getXkbBinding(seat.handle, @intFromEnum(keysym), binding.modifiers) catch unreachable;
                XkbBinding.inject(xkb_binding_handle, seat, binding.action);
            },
            .button => |button| {
                const pointer_binding_handle = seat.handle.getPointerBinding(@intFromEnum(button), binding.modifiers) catch unreachable;
                PointerBinding.inject(pointer_binding_handle, seat, binding.action);
            },
        }
    }
    seat.focus(window_manager.windows.last());
    window_manager.seats.append(seat);
    util.log.debug("{f} has been created.", .{seat});
}

pub fn destroy(self: *Self) void {
    util.log.debug("{f} is about to be destroyed.", .{self});
    var xkb_binding_iterator = self.xkb_bindings.iterator(.forward);
    while (xkb_binding_iterator.next()) |xkb_binding| xkb_binding.destroy();
    var pointer_binding_iterator = self.pointer_bindings.iterator(.forward);
    while (pointer_binding_iterator.next()) |pointer_binding| pointer_binding.destroy();
    self.focus(null);
    self.link.remove();
    self.handle.destroy();
    std.heap.c_allocator.destroy(self);
}

pub fn iterate(self: *Self, dir: wl.list.Direction) *Self {
    var link: *wl.list.Link = &self.link;
    return while (true) {
        link = switch (dir) {
            .forward => link.next.?,
            .reverse => link.prev.?,
        };
        if (link == &self.window_manager.seats.link) continue;
        break @fieldParentPtr("link", link);
    };
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("seat#{d}", .{self.handle.getId()});
}

pub fn manage(self: *Self) void {
    if (self.new) {
        self.enable();
        self.new = false;
    }

    switch (self.action) {
        .nop => {},
        .toggle_passthrough => {
            if (self.enabled) self.disable() else self.enable();
        },
        .spawn => |cmd| {
            var child = std.process.Child.init(cmd, std.heap.c_allocator);
            child.spawn() catch {};
        },
        .toggle_window_sticky => {
            if (self.window) |window| window.toggleSticky();
        },
        .focus_window => |index| {
            if (self.window) |window| {
                if (window.output) |output| {
                    var counter: i32 = 0;
                    var window_iterator = self.window_manager.windows.iterator(.forward);
                    while (window_iterator.next()) |each_window| {
                        if (each_window.output == output) {
                            counter += 1;
                            if (counter == index) {
                                self.focus(each_window);
                                break;
                            }
                        }
                    }
                }
            }
        },
        .iterate_window => |dir| {
            if (self.window) |window| {
                if (window.output) |output| {
                    var each_window = window.iterate(dir);
                    while (each_window != window) : (each_window = each_window.iterate(dir)) {
                        if (each_window.output == output) {
                            self.focus(each_window);
                            break;
                        }
                    }
                }
            }
        },
        .iterate_output => |dir| {
            if (self.window) |window| {
                if (window.output) |output| {
                    var each_output = output.iterate(dir);
                    each_output: while (each_output != output) : (each_output = each_output.iterate(dir)) {
                        var window_iterator = self.window_manager.windows.iterator(.forward);
                        while (window_iterator.next()) |each_window| {
                            if (each_window.output == each_output) {
                                self.focus(each_window);
                                break :each_output;
                            }
                        }
                    }
                }
            }
        },
        .swap_window => |dir| {
            if (self.window) |window| {
                if (window.output) |output| {
                    var each_window = window.iterate(dir);
                    while (each_window != window) : (each_window = each_window.iterate(dir)) {
                        if (each_window.output == output) {
                            window.swap(each_window);
                            break;
                        }
                    }
                }
            }
        },
        .send_window => |dir| {
            if (self.window) |window| {
                if (window.output) |output| {
                    window.send(output.iterate(dir));
                }
            }
        },
        .close_window => {
            if (self.window) |window| window.close();
        },
        .quit => self.window_manager.quit(),
        else => util.log.debug("{f} ignored {s} action.", .{ self, @tagName(self.action) }),
    }
    self.action = .nop;
}

pub fn enable(self: *Self) void {
    var xkb_binding_iterator = self.xkb_bindings.iterator(.forward);
    while (xkb_binding_iterator.next()) |xkb_binding| xkb_binding.handle.enable();
    var pointer_binding_iterator = self.pointer_bindings.iterator(.forward);
    while (pointer_binding_iterator.next()) |pointer_binding| pointer_binding.handle.enable();
    self.enabled = true;
    util.log.debug("{f} has been enabled.", .{self});
}

pub fn disable(self: *Self) void {
    var xkb_binding_iterator = self.xkb_bindings.iterator(.forward);
    while (xkb_binding_iterator.next()) |xkb_binding| if (xkb_binding.action != .toggle_passthrough) xkb_binding.handle.disable();
    var pointer_binding_iterator = self.pointer_bindings.iterator(.forward);
    while (pointer_binding_iterator.next()) |pointer_binding| if (pointer_binding.action != .toggle_passthrough) pointer_binding.handle.disable();
    self.enabled = false;
    util.log.debug("{f} has been disabled.", .{self});
}

pub fn focus(self: *Self, window: ?*Window) void {
    if (self.window == window) return;
    if (self.window) |old_window| {
        old_window.dirty = true;
        if (!old_window.sticky) {
            if (old_window.output) |output| output.dirty = true;
        }
    }
    self.window = window;
    if (self.window) |new_window| {
        new_window.dirty = true;
        if (!new_window.visible) {
            if (new_window.output) |output| output.dirty = true;
        }
    }
}
