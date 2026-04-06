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
        toggle_window_sticky,
        toggle_window_fullscreen,
        iterate_window_weight: wl.list.Direction,
        iterate_window_focus: wl.list.Direction,
        iterate_sticky_window_focus: wl.list.Direction,
        iterate_window_order: wl.list.Direction,
        iterate_output_view: wl.list.Direction,
        iterate_output_focus: wl.list.Direction,
        iterate_window_output: wl.list.Direction,
        set_window_focus: u32,
        set_window_weight: u4,
        set_output_view: u4,
        close_window,
        enable_window_floating,
        disable_window_floating,
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
enabled_updated: bool = true,
enabled: bool = true,

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

pub fn toggle(self: *Self) void {
    if (self.mapper.action != .toggle_passthrough) {
        self.enabled = !self.enabled;
        self.enabled_updated = true;
    }
}

fn execute(_: *Self) void {}

pub fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (self.river_binding) {
        .xkb => |river_xkb_binding| try writer.print("xkb_binding#{d}", .{river_xkb_binding.getId()}),
        .pointer => |river_pointer_binding| try writer.print("pointer_binding#{d}", .{river_pointer_binding.getId()}),
    }
}
