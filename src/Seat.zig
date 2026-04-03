const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const config = @import("config.zig");
const util = @import("util.zig");
const log = util.log;
const Rect = util.Rect;
const hit = util.hit;
const Binding = util.Binding;
const Action = util.Action;
const WindowManager = @import("WindowManager.zig");
const XkbBinding = @import("XkbBinding.zig");
const PointerBinding = @import("PointerBinding.zig");
const Window = @import("Window.zig");

const Self = @This();

window_manager: *WindowManager,
river_seat: *river.SeatV1,
link: wl.list.Link = undefined,
xkb_bindings: wl.list.Head(XkbBinding, .link) = undefined,
pointer_bindings: wl.list.Head(PointerBinding, .link) = undefined,
new: bool = true,
enabled: bool = false,
action: ?Action = null,
window: ?*Window = null,
x: i32 = undefined,
y: i32 = undefined,

pub fn bind(window_manager: *WindowManager, river_seat: *river.SeatV1) void {
    const self = std.heap.c_allocator.create(Self) catch unreachable;
    river_seat.setListener(*Self, river_seat_listener, self);
    self.* = .{
        .window_manager = window_manager,
        .river_seat = river_seat,
    };

    self.xkb_bindings.init();
    self.pointer_bindings.init();
    for (&config.bindings) |*binding| {
        switch (binding.trigger) {
            .keysym => |keysym| {
                const river_xkb_binding = window_manager.river_xkb_bindings.getXkbBinding(river_seat, @intFromEnum(keysym), binding.modifiers) catch unreachable;
                XkbBinding.bind(self, river_xkb_binding, binding.action);
            },
            .button => |button| {
                const river_pointer_binding = river_seat.getPointerBinding(@intFromEnum(button), binding.modifiers) catch unreachable;
                PointerBinding.bind(self, river_pointer_binding, binding.action);
            },
        }
    }

    self.link.init();
    window_manager.seats.append(self);

    self.focus(window_manager.windows.last());

    log.debug("{f} has been created.", .{self});
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    self.focus(null);

    self.link.remove();

    var xkb_binding_iterator = self.xkb_bindings.iterator(.forward);
    while (xkb_binding_iterator.next()) |xkb_binding| xkb_binding.destroy();
    var pointer_binding_iterator = self.pointer_bindings.iterator(.forward);
    while (pointer_binding_iterator.next()) |pointer_binding| pointer_binding.destroy();

    self.river_seat.destroy();
    std.heap.c_allocator.destroy(self);
}

fn river_seat_listener(_: *river.SeatV1, event: river.SeatV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .removed => {
            self.destroy();
        },
        .pointer_position => |position| {
            self.x = position.x;
            self.y = position.y;
        },
        .shell_surface_interaction => {
            var window_iterator = self.window_manager.windows.iterator(.forward);
            while (window_iterator.next()) |window| {
                if (hit(self.x, self.y, window.buttons[0]) or hit(self.x, self.y, window.buttons[0])) {
                    self.focus(window);
                    return;
                }
            }
            var output_iterator = self.window_manager.outputs.iterator(.forward);
            while (output_iterator.next()) |output| {
                for (output.buttons, 1..) |button, index| {
                    if (hit(self.x, self.y, button)) {
                        output.setView(@intCast(index));
                        return;
                    }
                }
            }
        },
        .wl_seat,
        .pointer_enter,
        .pointer_leave,
        .window_interaction,
        .op_delta,
        .op_release,
        => {
            log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
}

pub fn manage(self: *Self) void {
    if (self.new) {
        var xkb_binding_iterator = self.xkb_bindings.iterator(.forward);
        while (xkb_binding_iterator.next()) |xkb_binding| xkb_binding.river_xkb_binding.enable();

        var pointer_binding_iterator = self.pointer_bindings.iterator(.forward);
        while (pointer_binding_iterator.next()) |pointer_binding| pointer_binding.river_pointer_binding.enable();

        self.enabled = true;
        self.new = false;
    }

    if (self.action) |action| {
        log.debug("{f} is about to perform {s} action.", .{ self, @tagName(action) });
        switch (action) {
            .toggle_passthrough => {
                self.enabled = !self.enabled;

                var xkb_binding_iterator = self.xkb_bindings.iterator(.forward);
                while (xkb_binding_iterator.next()) |xkb_binding| {
                    if (xkb_binding.action != .toggle_passthrough) {
                        if (self.enabled) {
                            xkb_binding.river_xkb_binding.enable();
                        } else {
                            xkb_binding.river_xkb_binding.disable();
                        }
                    }
                }

                var pointer_binding_iterator = self.pointer_bindings.iterator(.forward);
                while (pointer_binding_iterator.next()) |pointer_binding| {
                    if (pointer_binding.action != .toggle_passthrough) {
                        if (self.enabled) {
                            pointer_binding.river_pointer_binding.enable();
                        } else {
                            pointer_binding.river_pointer_binding.disable();
                        }
                    }
                }
            },
            .spawn => |cmd| {
                util.spawn(cmd);
            },
            .toggle_window_sticky => {
                if (self.window) |window| {
                    if (window.output) |output| {
                        if (window.sticky) {
                            var window_iterator = self.window_manager.windows.iterator(.forward);
                            while (window_iterator.next()) |each_window| {
                                if (each_window.output == output) {
                                    each_window.setSticky(false);
                                }
                            }
                        } else {
                            window.setSticky(true);
                        }
                    }
                }
            },
            .iterate_window_weight => |dir| {
                if (self.window) |window| {
                    const weight = switch (dir) {
                        .forward => window.weight + 1,
                        .reverse => window.weight - 1,
                    };
                    window.setWeight(weight);
                }
            },
            .iterate_window_focus => |dir| {
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
            .iterate_sticky_window_focus => |dir| {
                if (self.window) |window| {
                    if (window.output) |output| {
                        var each_window = window.iterate(dir);
                        while (each_window != window) : (each_window = each_window.iterate(dir)) {
                            if (each_window.output == output and each_window.sticky) {
                                self.focus(each_window);
                                break;
                            }
                        }
                    }
                }
            },
            .iterate_window_order => |dir| {
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
            .iterate_output_view => |dir| {
                if (self.window) |window| {
                    if (window.output) |output| {
                        const view = switch (dir) {
                            .forward => output.view + 1,
                            .reverse => output.view - 1,
                        };
                        output.setView(view);
                    }
                }
            },
            .iterate_output_focus => |dir| {
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
            .iterate_window_output => |dir| {
                if (self.window) |window| {
                    if (window.output) |output| {
                        window.send(output.iterate(dir));
                    }
                }
            },
            .set_window_focus => |index| {
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
            .set_window_weight => |weight| {
                if (self.window) |window| window.setWeight(@intCast(weight));
            },
            .set_output_view => |view| {
                if (self.window) |window| {
                    if (window.output) |output| output.setView(view);
                }
            },
            .close_window => {
                if (self.window) |window| window.river_window.close();
            },
            .quit => {
                self.window_manager.running = false;
            },
        }
        self.action = null;
    }
}

pub fn focus(self: *Self, window: ?*Window) void {
    if (self.window == window) return;
    if (self.window) |old_window| {
        old_window.dirty = true;
        if (old_window.output) |output| {
            output.bar.dirty = true;
            if (!old_window.sticky) output.dirty = true;
        }
    }
    self.window = window;
    if (self.window) |new_window| {
        if (!new_window.focused) {
            new_window.dirty = true;
        }
        if (new_window.output) |output| {
            if (!new_window.focused) output.bar.dirty = true;
            if (!new_window.visible) output.dirty = true;
        }
    }
}

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("seat#{d}", .{self.river_seat.getId()});
}
