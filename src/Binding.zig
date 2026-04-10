const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;
const Modifiers = river.SeatV1.Modifiers;
const xkbcommon = @import("xkbcommon");

const util = @import("util.zig");
const log = util.log;
const Seat = @import("Seat.zig");

pub const Mapper = struct {
    modifiers: river.SeatV1.Modifiers,
    trigger: union(enum) {
        keysym: xkbcommon.Keysym,
        button: enum(u32) {
            left = 0x110,
            right = 0x111,
        },
    },
    action: union(enum) {
        toggle_passthrough,
        spawn: []const []const u8,
        iterate_window_weight: wl.list.Direction,
        iterate_window_focus: wl.list.Direction,
        iterate_sticky_window_focus: wl.list.Direction,
        iterate_window_order: wl.list.Direction,
        iterate_sticky_window_order: wl.list.Direction,
        iterate_output_focus: wl.list.Direction,
        iterate_window_output: wl.list.Direction,
        change_window_focus: u32,
        change_window_weight: u4,
        change_output_view: u4,
        close_window,
        toggle_window_sticky,
        toggle_window_fullscreen,
        enable_window_floating,
        disable_window_floating,
        refresh,
        quit,
    },
};

const Self = @This();

allocator: std.mem.Allocator,
seat: *Seat,
mapper: *const Mapper,
river_binding: union(enum) {
    xkb: *river.XkbBindingV1,
    pointer: *river.PointerBindingV1,
} = undefined,
link: wl.list.Link = undefined,
enabled_updated: bool = false,
enabled: bool = false,

pub fn create(seat: *Seat, mapper: *const Mapper) *Self {
    const self = seat.allocator.create(Self) catch unreachable;
    self.* = .{
        .allocator = seat.allocator,
        .seat = seat,
        .mapper = mapper,
    };

    switch (mapper.trigger) {
        .keysym => |keysym| {
            const river_xkb_binding = seat.window_manager.river_xkb_bindings.getXkbBinding(seat.river_seat, @intFromEnum(keysym), mapper.modifiers) catch unreachable;
            river_xkb_binding.setListener(*Self, river_xkb_binding_listener, self);
            self.river_binding = .{ .xkb = river_xkb_binding };
        },
        .button => |button| {
            const river_pointer_binding = seat.river_seat.getPointerBinding(@intFromEnum(button), mapper.modifiers) catch unreachable;
            river_pointer_binding.setListener(*Self, river_pointer_binding_listener, self);
            self.river_binding = .{ .pointer = river_pointer_binding };
        },
    }
    self.link.init();

    log.debug("{f} has been created.", .{self});
    return self;
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    self.link.remove();
    switch (self.river_binding) {
        .xkb => |river_xkb_binding| river_xkb_binding.destroy(),
        .pointer => |river_pointer_binding| river_pointer_binding.destroy(),
    }
    self.allocator.destroy(self);
}

fn river_xkb_binding_listener(_: *river.XkbBindingV1, event: river.XkbBindingV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .pressed => {
            self.execute();
        },
        .released => {
            log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
}

fn river_pointer_binding_listener(_: *river.PointerBindingV1, event: river.PointerBindingV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .pressed => {
            self.execute();
        },
        .released => {
            log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
}

pub fn manage(self: *Self) void {
    if (self.enabled_updated) {
        self.enabled_updated = false;

        if (self.enabled) {
            switch (self.river_binding) {
                .xkb => |river_xkb_binding| river_xkb_binding.enable(),
                .pointer => |river_pointer_binding| river_pointer_binding.enable(),
            }
        } else {
            switch (self.river_binding) {
                .xkb => |river_xkb_binding| river_xkb_binding.disable(),
                .pointer => |river_pointer_binding| river_pointer_binding.disable(),
            }
        }
        log.debug("{f} has been {s}.", .{ self, if (self.enabled) "enabled" else "disabled" });
    }
}

pub fn switchEnabled(self: *Self, enabled_or_null: ?bool) void {
    const enabled = if (enabled_or_null) |nonull_enabled| nonull_enabled else !self.enabled;
    if (enabled == self.enabled) return;
    self.enabled = enabled;
    self.enabled_updated = true;
}

fn execute(self: *Self) void {
    const seat = self.seat;
    const window_manager = seat.window_manager;
    switch (self.mapper.action) {
        .toggle_passthrough => {
            var binding_iterator = seat.bindings.iterator(.forward);
            while (binding_iterator.next()) |binding| {
                if (binding.mapper.action != .toggle_passthrough) binding.switchEnabled(null);
            }
        },
        .spawn => |cmd| {
            util.spawn(cmd, self.allocator);
        },
        .iterate_window_weight => |dir| {
            if (seat.focused) |window| {
                switch (dir) {
                    .forward => if (window.weight < 10) window.changeWeight(window.weight + 1),
                    .reverse => if (window.weight > 1) window.changeWeight(window.weight - 1),
                }
            }
        },
        .iterate_window_focus => |dir| {
            if (seat.focused) |window| {
                if (window.placed) |output| {
                    var next_window = window.iterate(dir);
                    while (next_window != window) : (next_window = next_window.iterate(dir)) {
                        if (next_window.placed == output) {
                            seat.focus(next_window);
                            break;
                        }
                    }
                }
            }
        },
        .iterate_sticky_window_focus => |dir| {
            if (seat.focused) |window| {
                if (window.placed) |output| {
                    var next_window = window.iterate(dir);
                    while (next_window != window) : (next_window = next_window.iterate(dir)) {
                        if (next_window.placed == output and next_window.sticky) {
                            seat.focus(next_window);
                            break;
                        }
                    }
                }
            }
        },
        .iterate_window_order => |dir| {
            if (seat.focused) |window| {
                if (window.placed) |output| {
                    var next_window = window.iterate(dir);
                    while (next_window != window) : (next_window = next_window.iterate(dir)) {
                        if (next_window.placed == output) {
                            window.swap(next_window);
                            break;
                        }
                    }
                }
            }
        },
        .iterate_sticky_window_order => |dir| {
            if (seat.focused) |window| {
                if (window.placed) |output| {
                    var next_window = window.iterate(dir);
                    while (next_window != window) : (next_window = next_window.iterate(dir)) {
                        if (next_window.placed == output and next_window.sticky) {
                            window.swap(next_window);
                            break;
                        }
                    }
                }
            }
        },
        .iterate_output_focus => |dir| {
            if (seat.focused) |window| {
                if (window.placed) |output| {
                    var next_output = output.iterate(dir);
                    next_output: while (next_output != output) : (next_output = next_output.iterate(dir)) {
                        var window_iterator = window_manager.windows.iterator(.forward);
                        while (window_iterator.next()) |each_window| {
                            if (each_window.placed == next_output) {
                                seat.focus(each_window);
                                break :next_output;
                            }
                        }
                    }
                }
            }
        },
        .iterate_window_output => |dir| {
            if (seat.focused) |window| {
                if (window.placed) |output| {
                    window.place(output.iterate(dir));
                }
            }
        },
        .change_window_focus => |index| {
            if (seat.focused) |window| {
                if (window.placed) |output| {
                    var counter: i32 = 0;
                    var window_iterator = window_manager.windows.iterator(.forward);
                    while (window_iterator.next()) |each_window| {
                        if (each_window.placed == output) {
                            counter += 1;
                            if (counter == index) {
                                seat.focus(each_window);
                                break;
                            }
                        }
                    }
                }
            }
        },
        .change_window_weight => |weight| {
            if (seat.focused) |window| window.changeWeight(weight);
        },
        .change_output_view => |view| {
            if (seat.focused) |window| {
                if (window.placed) |output| {
                    const first_sticky_window_or_null = output.changeView(view);
                    if (first_sticky_window_or_null) |first_sticky_window| {
                        seat.focus(first_sticky_window);
                    }
                }
            }
        },
        .close_window => {
            if (seat.focused) |window| window.close = true;
        },
        .toggle_window_sticky => {
            if (seat.focused) |window| window.switchSticky(null);
        },
        .toggle_window_fullscreen => {
            if (seat.focused) |window| window.switchFullscreen(null);
        },
        .enable_window_floating => {
            if (seat.hovered) |window| {
                var edges: river.WindowV1.Edges = .{};
                const left: i32 = window.area.x + @divFloor(window.area.w, 4);
                const right: i32 = window.area.x + @divFloor(window.area.w * 3, 4);
                const top: i32 = window.area.y + @divFloor(window.area.h, 4);
                const bottom: i32 = window.area.y + @divFloor(window.area.h * 3, 4);
                if (seat.x < left) edges.left = true else if (seat.x > right) edges.right = true;
                if (seat.y < top) edges.top = true else if (seat.y > bottom) edges.bottom = true;
                if (edges.left or edges.right or edges.top or edges.bottom) {
                    seat.resize(window, edges);
                } else {
                    seat.move(window);
                }
            }
        },
        .disable_window_floating => {
            if (seat.hovered) |window| {
                seat.focus(window);
                window.switchFloating(false);
            }
        },
        .refresh => {
            var output_iterator = window_manager.outputs.iterator(.forward);
            while (output_iterator.next()) |output| {
                output.dirty = true;
                output.bar.dirty = true;
            }
        },
        .quit => {
            window_manager.river_window_manager.exitSession();
        },
    }
}

pub fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (self.river_binding) {
        .xkb => |river_xkb_binding| try writer.print("xkb_binding#{d}", .{river_xkb_binding.getId()}),
        .pointer => |river_pointer_binding| try writer.print("pointer_binding#{d}", .{river_pointer_binding.getId()}),
    }
}
