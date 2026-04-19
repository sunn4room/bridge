const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;
const Modifiers = river.SeatV1.Modifiers;

const util = @import("util.zig");
const log = util.log;
const Seat = @import("Seat.zig");

pub const Mapper = struct {
    modifiers: river.SeatV1.Modifiers,
    trigger: union(enum) {
        keysym: enum(u32) {
            F1 = 0xffbe,
            F2 = 0xffbf,
            F3 = 0xffc0,
            F4 = 0xffc1,
            F5 = 0xffc2,
            F6 = 0xffc3,
            F7 = 0xffc4,
            F8 = 0xffc5,
            F9 = 0xffc6,
            F10 = 0xffc7,
            F11 = 0xffc8,
            @"0" = 0x0030,
            @"1" = 0x0031,
            @"2" = 0x0032,
            @"3" = 0x0033,
            @"4" = 0x0034,
            @"5" = 0x0035,
            @"6" = 0x0036,
            @"7" = 0x0037,
            @"8" = 0x0038,
            @"9" = 0x0039,
            a = 0x0061,
            b = 0x0062,
            c = 0x0063,
            d = 0x0064,
            e = 0x0065,
            f = 0x0066,
            g = 0x0067,
            h = 0x0068,
            i = 0x0069,
            j = 0x006a,
            k = 0x006b,
            l = 0x006c,
            m = 0x006d,
            n = 0x006e,
            o = 0x006f,
            p = 0x0070,
            q = 0x0071,
            r = 0x0072,
            s = 0x0073,
            t = 0x0074,
            u = 0x0075,
            v = 0x0076,
            w = 0x0077,
            x = 0x0078,
            y = 0x0079,
            z = 0x007a,
            Escape = 0xff1b,
            Tab = 0xff09,
            BackSpace = 0xff08,
            Return = 0xff0d,
            grave = 0x0060,
            minus = 0x002d,
            equal = 0x003d,
            bracketleft = 0x005b,
            bracketright = 0x005d,
            backslash = 0x005c,
            semicolon = 0x003b,
            apostrophe = 0x0027,
            comma = 0x002c,
            period = 0x002e,
            slash = 0x002f,
            space = 0x0020,
        },
        button: enum(u32) {
            left = 0x110,
            right = 0x111,
        },
    },
    action: union(enum) {
        reload_config,
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
        show_window_info,
        quit,
    },
    allow_when_locked: bool = false,
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
toggle: bool = false,
locked: bool = false,

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

pub fn switchToggle(self: *Self, toggle_or_null: ?bool) void {
    const toggle = if (toggle_or_null) |nonull_toggle| nonull_toggle else !self.toggle;
    if (toggle == self.toggle) return;
    self.toggle = toggle;
    self.update_enabled();
}

pub fn switchLocked(self: *Self, locked_or_null: ?bool) void {
    const locked = if (locked_or_null) |nonull_locked| nonull_locked else !self.locked;
    if (locked == self.locked) return;
    self.locked = locked;
    self.update_enabled();
}

pub fn update_enabled(self: *Self) void {
    const enabled = !self.locked and self.toggle;
    if (enabled == self.enabled) return;
    self.enabled = enabled;
    self.enabled_updated = true;
}

fn execute(self: *Self) void {
    const seat = self.seat;
    const window_manager = seat.window_manager;
    switch (self.mapper.action) {
        .reload_config => {
            self.seat.window_manager.updateConfig();
        },
        .toggle_passthrough => {
            var binding_iterator = seat.bindings.iterator(.forward);
            while (binding_iterator.next()) |binding| {
                if (binding != self) binding.switchToggle(null);
            }
        },
        .spawn => |cmd| {
            util.spawn(cmd) catch {};
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
                    const sticky_window_or_null = output.changeView(view);
                    if (sticky_window_or_null) |sticky_window| {
                        seat.focus(sticky_window);
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
        .show_window_info => {
            if (seat.focused) |window| {
                const info = std.fmt.allocPrintSentinel(self.allocator, "appid: {s}\ntitle: {s}", .{
                    if (window.app_id) |app_id| app_id else "",
                    if (window.title) |title| title else "",
                }, 0) catch unreachable;
                defer self.allocator.free(info);
                util.spawn(&.{ "notify-send", "Window Info", info }) catch {};
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
