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
river_layer_shell_seat: *river.LayerShellSeatV1,
link: wl.list.Link = undefined,
xkb_bindings: wl.list.Head(XkbBinding, .link) = undefined,
pointer_bindings: wl.list.Head(PointerBinding, .link) = undefined,
new: bool = true,
layer_focus: LayerFocus = .none,
enabled: bool = false,
action: ?Action = null,
hovered: ?*Window = null,
focused: ?*Window = null,
x: i32 = undefined,
y: i32 = undefined,
op: ?Operation = null,

pub fn bind(window_manager: *WindowManager, river_seat: *river.SeatV1) void {
    const self = std.heap.c_allocator.create(Self) catch unreachable;
    river_seat.setListener(*Self, river_seat_listener, self);
    const river_layer_shell_seat = window_manager.river_layer_shell.getSeat(river_seat) catch unreachable;
    river_layer_shell_seat.setListener(*Self, river_layer_shell_seat_listener, self);
    self.* = .{
        .window_manager = window_manager,
        .river_seat = river_seat,
        .river_layer_shell_seat = river_layer_shell_seat,
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
        .window_interaction => |interaction| {
            if (interaction.window) |river_window| {
                self.focus(@ptrCast(@alignCast(river_window.getUserData().?)));
            }
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
        .pointer_enter => |enter| {
            if (enter.window) |river_window| {
                self.hovered = @ptrCast(@alignCast(river_window.getUserData().?));
            }
        },
        .pointer_leave => {
            self.hovered = null;
        },
        .op_delta => |delta| {
            self.op.?.dx = delta.dx;
            self.op.?.dy = delta.dy;
        },
        .op_release => {
            self.op.?.running = false;
        },
        .wl_seat,
        => {
            log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
}

fn river_layer_shell_seat_listener(_: *river.LayerShellSeatV1, event: river.LayerShellSeatV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .focus_exclusive => self.layer_focus = .exclusive,
        .focus_non_exclusive => self.layer_focus = .non_exclusive,
        .focus_none => self.layer_focus = .none,
    }
}

pub const LayerFocus = enum {
    exclusive,
    non_exclusive,
    none,
};

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
                if (self.focused) |window| {
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
            .toggle_window_fullscreen => {
                if (self.focused) |window| {
                    if (window.output) |output| {
                        if (output.fullscreen == window) {
                            output.setFullScreen(null);
                        } else {
                            output.setFullScreen(window);
                        }
                    }
                }
            },
            .iterate_window_weight => |dir| {
                if (self.focused) |window| {
                    const weight = switch (dir) {
                        .forward => window.weight + 1,
                        .reverse => window.weight - 1,
                    };
                    window.setWeight(weight);
                }
            },
            .iterate_window_focus => |dir| {
                if (self.focused) |window| {
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
                if (self.focused) |window| {
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
                if (self.focused) |window| {
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
                if (self.focused) |window| {
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
                if (self.focused) |window| {
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
                if (self.focused) |window| {
                    if (window.output) |output| {
                        window.send(output.iterate(dir));
                    }
                }
            },
            .set_window_focus => |index| {
                if (self.focused) |window| {
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
                if (self.focused) |window| window.setWeight(@intCast(weight));
            },
            .set_output_view => |view| {
                if (self.focused) |window| {
                    if (window.output) |output| {
                        output.setView(view);
                        var window_iterator = self.window_manager.windows.iterator(.forward);
                        while (window_iterator.next()) |each_window| {
                            if (each_window.output == output and each_window.views & (@as(u10, 1) << (output.view - 1)) != 0) {
                                self.focus(each_window);
                                break;
                            }
                        }
                    }
                }
            },
            .close_window => {
                if (self.focused) |window| window.river_window.close();
            },
            .enable_window_floating => {
                if (self.hovered) |window| {
                    var edges: river.WindowV1.Edges = .{};
                    const left: i32 = window.area.x + @divFloor(window.area.w, 4);
                    const right: i32 = window.area.x + @divFloor(window.area.w * 3, 4);
                    const top: i32 = window.area.y + @divFloor(window.area.h, 4);
                    const bottom: i32 = window.area.y + @divFloor(window.area.h * 3, 4);
                    if (self.x < left) edges.left = true else if (self.x > right) edges.right = true;
                    if (self.y < top) edges.top = true else if (self.y > bottom) edges.bottom = true;
                    if (edges.left or edges.right or edges.top or edges.bottom) {
                        self.resize(window, edges);
                    } else {
                        self.move(window);
                    }
                }
            },
            .disable_window_floating => {
                if (self.hovered) |window| {
                    self.focus(window);
                    window.setFloating(false);
                }
            },
            .quit => {
                self.window_manager.river_window_manager.exitSession();
            },
        }
        self.action = null;
    }

    if (self.focused == null) {
        self.river_seat.clearFocus();
    } else if (self.op) |*op| {
        if (self.focused != op.window or op.running == false) {
            self.river_seat.opEnd();
            switch (op.data) {
                .resize => op.window.river_window.informResizeEnd(),
                else => {},
            }
            self.op = null;
        } else if (op.running == null) {
            op.running = true;
            self.river_seat.opStartPointer();
            switch (op.data) {
                .resize => op.window.river_window.informResizeStart(),
                else => {},
            }
        } else {
            switch (op.data) {
                .move => |data| {
                    const x: i32 = data.x + op.dx;
                    const y: i32 = data.y + op.dy;
                    op.window.river_node.setPosition(x, y);
                    op.window.area.x = x;
                    op.window.area.y = y;
                },
                .resize => |data| {
                    var x: i32 = data.x;
                    var y: i32 = data.y;
                    var w: u31 = data.w;
                    var h: u31 = data.h;
                    if (data.edges.left) {
                        if (data.w - op.dx > 0) {
                            x = data.x + op.dx;
                            w = @intCast(data.w - op.dx);
                        }
                    } else if (data.edges.right) {
                        w = @intCast(data.w + op.dx);
                    }
                    if (data.edges.top) {
                        if (data.h - op.dy > 0) {
                            y = data.y + op.dy;
                            h = @intCast(data.h - op.dy);
                        }
                    } else if (data.edges.bottom) {
                        h = @intCast(data.h + op.dy);
                    }
                    op.window.river_node.setPosition(x, y);
                    op.window.river_window.proposeDimensions(w, h);
                    op.window.area.x = x;
                    op.window.area.y = y;
                    op.window.area.w = w;
                    op.window.area.h = h;
                },
            }
        }
    }
}

pub fn focus(self: *Self, original_window: ?*Window) void {
    var window: ?*Window = original_window;

    if (window) |nonull_window| {
        if (nonull_window.output) |output| {
            if (output.fullscreen) |fullscreen| window = fullscreen;
        }
    }

    switch (self.layer_focus) {
        .exclusive => return,
        .non_exclusive => if (window != null) {
            self.layer_focus = .none;
        },
        .none => {},
    }

    if (self.focused == window) return;
    if (self.focused) |old_window| {
        old_window.dirty = true;
        if (old_window.output) |output| {
            output.bar.dirty = true;
            if (!old_window.sticky) output.dirty = true;
        }
    }
    self.focused = window;
    if (self.focused) |new_window| {
        if (!new_window.focused) {
            new_window.dirty = true;
        }
        if (new_window.output) |output| {
            if (!new_window.focused) output.bar.dirty = true;
            if (!new_window.visible) output.dirty = true;
        }
    }
}

pub fn move(self: *Self, window: *Window) void {
    if (self.op != null) return;
    self.focus(window);
    window.setFloating(true);
    self.op = .{
        .window = window,
        .data = .{
            .move = .{
                .x = window.area.x,
                .y = window.area.y,
            },
        },
    };
}

pub fn resize(self: *Self, window: *Window, edges: river.WindowV1.Edges) void {
    if (self.op != null) return;
    self.focus(window);
    window.setFloating(true);
    self.op = .{
        .window = window,
        .data = .{
            .resize = .{
                .edges = edges,
                .x = window.area.x,
                .y = window.area.y,
                .w = window.area.w,
                .h = window.area.h,
            },
        },
    };
}

const Move = struct {
    x: i32,
    y: i32,
};

const Resize = struct {
    edges: river.WindowV1.Edges,
    x: i32,
    y: i32,
    w: u31,
    h: u31,
};

const OperationData = union(enum) {
    move: Move,
    resize: Resize,
};

const Operation = struct {
    window: *Window,
    data: OperationData,
    dx: i32 = 0,
    dy: i32 = 0,
    running: ?bool = null,
};

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("seat#{d}", .{self.river_seat.getId()});
}
