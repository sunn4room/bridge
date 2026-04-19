const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const Config = @import("Config.zig");
const util = @import("util.zig");
const log = util.log;
const Rect = util.Rect;
const WindowManager = @import("WindowManager.zig");
const Binding = @import("Binding.zig");
const Window = @import("Window.zig");

const LayerFocus = enum {
    exclusive,
    non_exclusive,
    none,
};

const Operation = struct {
    window: ?*Window,
    data: union(enum) {
        move: struct {
            x: i32,
            y: i32,
        },
        resize: struct {
            edges: river.WindowV1.Edges,
            x: i32,
            y: i32,
            w: i32,
            h: i32,
        },
    },
    dx: i32 = 0,
    dy: i32 = 0,
    state: enum {
        created,
        running,
        stopped,
    } = .created,
};

const Self = @This();

allocator: std.mem.Allocator,
window_manager: *WindowManager,
river_seat: *river.SeatV1,
river_layer_shell_seat: *river.LayerShellSeatV1,
link: wl.list.Link = undefined,
config: *const Config = undefined,
bindings: wl.list.Head(Binding, .link) = undefined,
layer_focus: LayerFocus = .none,
hovered: ?*Window = null,
x: i32 = undefined,
y: i32 = undefined,
focused_updated: bool = false,
focused: ?*Window = null,
operation_updated: bool = false,
operation: ?struct {
    window: ?*Window,
    data: union(enum) {
        move: struct {
            x: i32,
            y: i32,
        },
        resize: struct {
            edges: river.WindowV1.Edges,
            x: i32,
            y: i32,
            w: i32,
            h: i32,
        },
    },
    dx: i32 = 0,
    dy: i32 = 0,
    state: enum {
        created,
        running,
        stopped,
    } = .created,
} = null,

pub fn create(window_manager: *WindowManager, river_seat: *river.SeatV1) *Self {
    const self = window_manager.allocator.create(Self) catch unreachable;
    self.* = .{
        .allocator = window_manager.allocator,
        .window_manager = window_manager,
        .river_seat = river_seat,
        .river_layer_shell_seat = window_manager.river_layer_shell.getSeat(river_seat) catch unreachable,
    };

    self.river_seat.setListener(*Self, river_seat_listener, self);
    self.river_layer_shell_seat.setListener(*Self, river_layer_shell_seat_listener, self);
    self.link.init();
    self.bindings.init();
    self.changeConfig(&self.window_manager.configw.?.config);

    log.debug("{f} has been created.", .{self});
    return self;
}

pub fn pre(self: *Self) void {
    self.focus(self.window_manager.windows.last());
}

pub fn post(self: *Self) void {
    self.focus(null);
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    var binding_iterator = self.bindings.iterator(.forward);
    while (binding_iterator.next()) |binding| binding.destroy();
    self.link.remove();
    self.river_layer_shell_seat.destroy();
    self.river_seat.destroy();
    self.allocator.destroy(self);
}

fn river_seat_listener(_: *river.SeatV1, event: river.SeatV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .removed => {
            self.post();
            self.destroy();
        },
        .pointer_position => |data| {
            self.x = data.x;
            self.y = data.y;
        },
        .window_interaction => |data| {
            if (data.window) |river_window| {
                const window: *Window = @ptrCast(@alignCast(river_window.getUserData().?));
                self.focus(window);
            }
        },
        .shell_surface_interaction => {
            var window_iterator = self.window_manager.windows.iterator(.forward);
            while (window_iterator.next()) |window| {
                for (&window.buttons) |*button| {
                    if (button.hit(self.x, self.y)) {
                        self.focus(window);
                        break;
                    }
                }
            } else {
                var output_iterator = self.window_manager.outputs.iterator(.forward);
                while (output_iterator.next()) |output| {
                    var counter: u4 = 0;
                    for (&output.buttons) |*button| {
                        counter += 1;
                        if (button.hit(self.x, self.y)) {
                            const sticky_window_or_null = output.changeView(counter);
                            if (sticky_window_or_null) |sticky_window| {
                                self.focus(sticky_window);
                            }
                            break;
                        }
                    }
                }
            }
        },
        .pointer_enter => |data| {
            if (data.window) |river_window| {
                self.hovered = @ptrCast(@alignCast(river_window.getUserData().?));
            }
        },
        .pointer_leave => {
            self.hovered = null;
        },
        .op_delta => |data| {
            if (self.operation) |*operation| {
                operation.dx = data.dx;
                operation.dy = data.dy;
                self.operation_updated = true;
            } else unreachable;
        },
        .op_release => {
            self.cancel(null);
        },
        else => {
            log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
}

fn river_layer_shell_seat_listener(_: *river.LayerShellSeatV1, event: river.LayerShellSeatV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .focus_exclusive => {
            self.layer_focus = .exclusive;
        },
        .focus_non_exclusive => {
            self.layer_focus = .non_exclusive;
        },
        .focus_none => {
            if (self.layer_focus != .none) {
                self.layer_focus = .none;
                self.focused_updated = true;
            }
        },
    }
}

pub fn manage(self: *Self) void {
    var binding_iterator = self.bindings.iterator(.forward);
    while (binding_iterator.next()) |binding| binding.manage();

    if (self.layer_focus != .exclusive) {
        if (self.focused_updated) {
            self.focused_updated = false;

            if (self.focused) |window| {
                self.river_seat.focusWindow(window.river_window);
                self.link.remove();
                self.window_manager.seats.prepend(self);
                if (window.placed) |output| {
                    output.river_layer_shell_output.setDefault();
                }
                self.layer_focus = .none;
                log.debug("{f} has focused on {f}.", .{ self, window });
            } else {
                self.river_seat.clearFocus();
                log.debug("{f} has cleared focus.", .{self});
            }
        }
    }

    if (self.operation_updated) {
        self.operation_updated = false;

        if (self.operation) |*operation| {
            switch (operation.state) {
                .stopped => {
                    if (operation.window) |window| {
                        switch (operation.data) {
                            .resize => {
                                window.river_window.informResizeEnd();
                                log.debug("{f} has been informed to end resize.", .{window});
                            },
                            else => {},
                        }
                    }
                    self.river_seat.opEnd();
                    log.debug("{f} has ended operation.", .{self});
                    self.operation = null;
                },
                .created => {
                    const window = operation.window.?;
                    switch (operation.data) {
                        .resize => {
                            window.river_window.informResizeStart();
                            log.debug("{f} has been informed to start resize.", .{window});
                        },
                        else => {},
                    }
                    self.river_seat.opStartPointer();
                    log.debug("{f} has started operation.", .{self});
                    operation.state = .running;
                },
                .running => {
                    const window = operation.window.?;
                    const output = window.placed.?;
                    var area: Rect = window.area;
                    switch (operation.data) {
                        .move => |data| {
                            area.x = data.x + operation.dx;
                            area.y = data.y + operation.dy;
                            if (!output.area.contain(&area)) return;
                            window.river_node.setPosition(area.x, area.y);
                            window.area = area;
                        },
                        .resize => |data| {
                            if (data.edges.left) {
                                if (data.w - operation.dx > 0) {
                                    area.x = data.x + operation.dx;
                                    area.w = data.w - operation.dx;
                                }
                            } else if (data.edges.right) {
                                area.w = data.w + operation.dx;
                            }
                            if (data.edges.top) {
                                if (data.h - operation.dy > 0) {
                                    area.y = data.y + operation.dy;
                                    area.h = data.h - operation.dy;
                                }
                            } else if (data.edges.bottom) {
                                area.h = data.h + operation.dy;
                            }
                            if (!output.area.contain(&area)) return;
                            window.river_node.setPosition(area.x, area.y);
                            window.river_window.proposeDimensions(area.w, area.h);
                            window.area = area;
                        },
                    }
                    log.info(
                        "{f} operated {f}: {}, {}, {}, {}",
                        .{
                            self,
                            window,
                            area.x,
                            area.y,
                            area.w,
                            area.h,
                        },
                    );
                },
            }
        } else unreachable;
    }
}

pub fn focus(self: *Self, original_window: ?*Window) void {
    var window: ?*Window = original_window;

    if (window) |notnull_window| {
        if (notnull_window.placed) |output| {
            if (output.fullscreen) |fullscreen| window = fullscreen;
        }
    }

    if (self.focused == window) return;

    self.cancel(null);

    if (self.focused) |old_window| old_window.focus(false);
    self.focused = window;
    self.focused_updated = true;
    if (self.focused) |new_window| new_window.focus(true);
}

pub fn move(self: *Self, window: *Window) void {
    if (self.operation != null) return;
    self.focus(window);

    if (self.focused != window) return;
    window.switchFloating(true);

    self.operation = .{
        .window = window,
        .data = .{
            .move = .{
                .x = window.area.x,
                .y = window.area.y,
            },
        },
    };
    self.operation_updated = true;
}

pub fn resize(self: *Self, window: *Window, edges: river.WindowV1.Edges) void {
    if (self.operation != null) return;
    self.focus(window);

    if (self.focused != window) return;
    window.switchFloating(true);

    self.operation = .{
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
    self.operation_updated = true;
}

pub fn cancel(self: *Self, window_or_null: ?*Window) void {
    if (self.operation) |*operation| {
        if (window_or_null) |window| {
            if (operation.window == window) {
                operation.window = null;
            } else {
                return;
            }
        }
        operation.state = .stopped;
        self.operation_updated = true;
    }
}

pub fn changeConfig(self: *Self, config: *const Config) void {
    self.config = config;
    self.updateBindings();
}

pub fn updateBindings(self: *Self) void {
    var binding_iterator = self.bindings.iterator(.forward);
    while (binding_iterator.next()) |binding| binding.destroy();

    const map = if (self.config.map) |map| map else Config.default.map.?;
    for (map) |*mapper| {
        const binding = Binding.create(self, mapper);
        self.bindings.append(binding);
        binding.switchToggle(true);
    }
}

pub fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("seat#{d}", .{self.river_seat.getId()});
}
