const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const wp = wayland.client.wp;
const river = wayland.client.river;
const fcft = @import("fcft");

const config = @import("config.zig");
const util = @import("util.zig");
const log = util.log;
const Seat = @import("Seat.zig");
const Window = @import("Window.zig");
const Output = @import("Output.zig");

const Self = @This();

allocator: std.mem.Allocator,
wl_registry: *wl.Registry = undefined,
wl_compositor: *wl.Compositor = undefined,
wl_compositor_name: ?u32 = null,
wl_shm: *wl.Shm = undefined,
wl_shm_name: ?u32 = null,
wp_viewporter: *wp.Viewporter = undefined,
wp_viewporter_name: ?u32 = null,
wp_fractional_scale_manager: *wp.FractionalScaleManagerV1 = undefined,
wp_fractional_scale_manager_name: ?u32 = null,
river_window_manager: *river.WindowManagerV1 = undefined,
river_window_manager_name: ?u32 = null,
river_xkb_bindings: *river.XkbBindingsV1 = undefined,
river_xkb_bindings_name: ?u32 = null,
river_layer_shell: *river.LayerShellV1 = undefined,
river_layer_shell_name: ?u32 = null,
seats: wl.list.Head(Seat, .link) = undefined,
windows: wl.list.Head(Window, .link) = undefined,
fwindows: wl.list.Head(Window, .flink) = undefined,
outputs: wl.list.Head(Output, .link) = undefined,
bar_height: i32 = undefined,
running: bool = false,

pub fn create(allocator: std.mem.Allocator, wl_display: *wl.Display) *Self {
    if (!fcft.init(.auto, false, .warning)) unreachable;
    if (fcft.capabilities() & fcft.Capabilities.text_run_shaping == 0) unreachable;

    const self = allocator.create(Self) catch unreachable;
    self.* = .{ .allocator = allocator };

    self.seats.init();
    self.windows.init();
    self.fwindows.init();
    self.outputs.init();

    const basic_font = util.getFont(120);
    defer basic_font.destroy();
    self.bar_height = @intCast(basic_font.height);

    self.wl_registry = wl_display.getRegistry() catch unreachable;
    self.wl_registry.setListener(*Self, wl_registry_listener, self);
    if (wl_display.roundtrip() != .SUCCESS) unreachable;

    log.debug("{f} has been created.", .{self});
    return self;
}

pub fn startup(self: *Self) void {
    if (self.wl_compositor_name == null) {
        log.err("Global object 'wl_compositor' is missing.", .{});
    } else if (self.wl_shm_name == null) {
        log.err("Global object 'wl_shm' is missing.", .{});
    } else if (self.wp_viewporter_name == null) {
        log.err("Global object 'wp_viewporter' is missing.", .{});
    } else if (self.wp_fractional_scale_manager_name == null) {
        log.err("Global object 'wp_fractional_scale_manager' is missing.", .{});
    } else if (self.river_window_manager_name == null) {
        log.err("Global object 'river_window_manager' is missing.", .{});
    } else if (self.river_xkb_bindings_name == null) {
        log.err("Global object 'river_xkb_bindings' is missing.", .{});
    } else if (self.river_layer_shell_name == null) {
        log.err("Global object 'river_layer_shell' is missing.", .{});
    } else {
        for (config.startup_cmds) |cmd| util.spawn(cmd, self.allocator);
        self.river_window_manager.setListener(*Self, river_window_manager_listener, self);

        self.running = true;
    }
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    var seat_iterator = self.seats.iterator(.forward);
    while (seat_iterator.next()) |seat| seat.destroy();
    var window_iterator = self.windows.iterator(.forward);
    while (window_iterator.next()) |window| window.destroy();
    var output_iterator = self.outputs.iterator(.forward);
    while (output_iterator.next()) |output| output.destroy();

    if (self.river_layer_shell_name != null) self.river_layer_shell.destroy();
    if (self.river_xkb_bindings_name != null) self.river_xkb_bindings.destroy();
    if (self.river_window_manager_name != null) self.river_window_manager.destroy();
    if (self.wp_fractional_scale_manager_name != null) self.wp_fractional_scale_manager.destroy();
    if (self.wp_viewporter_name != null) self.wp_viewporter.destroy();
    if (self.wl_shm_name != null) self.wl_shm.destroy();
    if (self.wl_compositor_name != null) self.wl_compositor.destroy();

    self.wl_registry.destroy();
    fcft.fini();
    self.allocator.destroy(self);
}

fn wl_registry_listener(_: *wl.Registry, event: wl.Registry.Event, self: *Self) void {
    switch (event) {
        .global => |global| {
            if (std.mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                self.wl_compositor = self.wl_registry.bind(global.name, wl.Compositor, 3) catch unreachable;
                self.wl_compositor_name = global.name;
            } else if (std.mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                self.wl_shm = self.wl_registry.bind(global.name, wl.Shm, 1) catch unreachable;
                self.wl_shm_name = global.name;
            } else if (std.mem.orderZ(u8, global.interface, wp.Viewporter.interface.name) == .eq) {
                self.wp_viewporter = self.wl_registry.bind(global.name, wp.Viewporter, 1) catch unreachable;
                self.wp_viewporter_name = global.name;
            } else if (std.mem.orderZ(u8, global.interface, wp.FractionalScaleManagerV1.interface.name) == .eq) {
                self.wp_fractional_scale_manager = self.wl_registry.bind(global.name, wp.FractionalScaleManagerV1, 1) catch unreachable;
                self.wp_fractional_scale_manager_name = global.name;
            } else if (std.mem.orderZ(u8, global.interface, river.WindowManagerV1.interface.name) == .eq) {
                self.river_window_manager = self.wl_registry.bind(global.name, river.WindowManagerV1, 4) catch unreachable;
                self.river_window_manager_name = global.name;
            } else if (std.mem.orderZ(u8, global.interface, river.XkbBindingsV1.interface.name) == .eq) {
                self.river_xkb_bindings = self.wl_registry.bind(global.name, river.XkbBindingsV1, 1) catch unreachable;
                self.river_xkb_bindings_name = global.name;
            } else if (std.mem.orderZ(u8, global.interface, river.LayerShellV1.interface.name) == .eq) {
                self.river_layer_shell = self.wl_registry.bind(global.name, river.LayerShellV1, 1) catch unreachable;
                self.river_layer_shell_name = global.name;
            }
        },
        .global_remove => |global| {
            if (global.name == self.wl_compositor_name) {
                log.err("Global object 'wl_compositor' is no longer available.", .{});
                self.running = false;
            } else if (global.name == self.wl_shm_name) {
                log.err("Global object 'wl_shm' is no longer available.", .{});
                self.running = false;
            } else if (global.name == self.wp_viewporter_name) {
                log.err("Global object 'wp_viewporter' is no longer available.", .{});
                self.running = false;
            } else if (global.name == self.wp_fractional_scale_manager_name) {
                log.err("Global object 'wp_fractional_scale_manager' is no longer available.", .{});
                self.running = false;
            } else if (global.name == self.river_window_manager_name) {
                log.err("Global object 'river_window_manager' is no longer available.", .{});
                self.running = false;
            } else if (global.name == self.river_xkb_bindings_name) {
                log.err("Global object 'river_xkb_bindings' is no longer available.", .{});
                self.running = false;
            } else if (global.name == self.river_layer_shell_name) {
                log.err("Global object 'river_layer_shell' is no longer available.", .{});
                self.running = false;
            }
        },
    }
}

fn river_window_manager_listener(_: *river.WindowManagerV1, event: river.WindowManagerV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .unavailable => {
            log.err("{f} is not available.", .{self});
            self.running = false;
        },
        .finished => {
            log.info("{f} will receive no further events.", .{self});
            self.running = false;
        },
        .seat => |data| {
            const river_seat = data.id;
            const seat = Seat.create(self, river_seat);

            self.seats.append(seat);
            seat.focus(self.fwindows.last());
        },
        .window => |data| {
            const river_window = data.id;
            const window = Window.create(self, river_window);

            self.fwindows.append(window);
            const last_focused_window = window.fiterate(.reverse);
            if (last_focused_window == window) {
                self.windows.append(window);
                window.place(self.outputs.first());
            } else {
                last_focused_window.link.insert(&window.link);
                window.place(last_focused_window.placed);
            }
            var seat_iterator = self.seats.iterator(.forward);
            while (seat_iterator.next()) |seat| seat.focus(window);
        },
        .output => |data| {
            const river_output = data.id;
            const output = Output.create(self, river_output);

            self.outputs.append(output);
            var window_iterator = self.windows.iterator(.forward);
            while (window_iterator.next()) |window| if (window.placed == null) window.place(output);
        },
        .manage_start => {
            var seat_iterator = self.seats.iterator(.forward);
            while (seat_iterator.next()) |seat| seat.manage();
            var window_iterator = self.windows.iterator(.forward);
            while (window_iterator.next()) |window| window.manage();
            var output_iterator = self.outputs.iterator(.forward);
            while (output_iterator.next()) |output| output.manage();

            self.river_window_manager.manageFinish();
            log.debug("{f} has finished manage sequence.\n", .{self});
        },
        .render_start => {
            self.river_window_manager.renderFinish();
            log.debug("{f} has finished render sequence.\n", .{self});
        },
        .session_locked,
        .session_unlocked,
        => {
            log.debug("{f} ignored {s} event.", .{ self, @tagName(event) });
        },
    }
}

pub fn format(_: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("window_manager", .{});
}
