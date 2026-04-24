const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const wp = wayland.client.wp;
const river = wayland.client.river;
const fcft = @import("fcft");

const Config = @import("Config.zig");
const util = @import("util.zig");
const log = util.log;
const Seat = @import("Seat.zig");
const Window = @import("Window.zig");
const Output = @import("Output.zig");
const Bar = @import("Bar.zig");
const InputDevice = @import("InputDevice.zig");

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
river_input_manager: *river.InputManagerV1 = undefined,
river_input_manager_name: ?u32 = null,
river_libinput_config: *river.LibinputConfigV1 = undefined,
river_libinput_config_name: ?u32 = null,
river_xkb_config: *river.XkbConfigV1 = undefined,
river_xkb_config_name: ?u32 = null,
river_home: [:0]const u8 = undefined,
bridge_zon: []const u8 = undefined,
config: *const Config = undefined,
seats: wl.list.Head(Seat, .link) = undefined,
windows: wl.list.Head(Window, .link) = undefined,
unavailable_windows: wl.list.Head(Window, .link) = undefined,
outputs: wl.list.Head(Output, .link) = undefined,
inputs: wl.list.Head(InputDevice, .link) = undefined,
bar_height: i32 = undefined,
running: bool = false,

pub fn create(allocator: std.mem.Allocator, wl_display: *wl.Display) *Self {
    if (!fcft.init(.auto, false, .warning)) unreachable;
    if (fcft.capabilities() & fcft.Capabilities.text_run_shaping == 0) unreachable;

    const self = allocator.create(Self) catch unreachable;
    self.* = .{ .allocator = allocator };

    const xdg_config_home_or_null = util.getEnv(allocator, "XDG_CONFIG_HOME");
    const config_home = if (xdg_config_home_or_null) |xdg_config_home| xdg_config_home else blk: {
        const home = util.getEnv(allocator, "HOME").?;
        defer allocator.free(home);
        break :blk std.fmt.allocPrint(allocator, "{s}/.config", .{home}) catch unreachable;
    };
    defer allocator.free(config_home);

    self.river_home = std.fmt.allocPrintSentinel(allocator, "{s}/river", .{config_home}, 0) catch unreachable;
    self.bridge_zon = std.fmt.allocPrint(allocator, "{s}/bridge.zon", .{self.river_home}) catch unreachable;

    self.seats.init();
    self.windows.init();
    self.unavailable_windows.init();
    self.outputs.init();
    self.inputs.init();

    self.config = Config.init(self.allocator, self.bridge_zon);
    self.update();

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
    } else if (self.river_input_manager_name == null) {
        log.err("Global object 'river_input_manager' is missing.", .{});
    } else if (self.river_libinput_config_name == null) {
        log.err("Global object 'river_libinput_config' is missing.", .{});
    } else if (self.river_xkb_config_name == null) {
        log.err("Global object 'river_xkb_config' is missing.", .{});
    } else {
        util.prepareSpawn();
        const cmd_startup = if (self.config.cmd_startup) |cmd_startup| cmd_startup else Config.default.cmd_startup.?;
        for (cmd_startup) |cmd| util.spawn(cmd);
        self.river_window_manager.setListener(*Self, river_window_manager_listener, self);
        self.river_input_manager.setListener(*Self, river_input_manager_listener, self);
        self.river_libinput_config.setListener(*Self, river_libinput_config_listener, self);
        self.river_xkb_config.setListener(*Self, river_xkb_config_listener, self);

        self.running = true;
    }
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    var seat_iterator = self.seats.iterator(.forward);
    while (seat_iterator.next()) |seat| seat.destroy();
    var window_iterator = self.windows.iterator(.forward);
    while (window_iterator.next()) |window| window.destroy();
    var unavailable_window_iterator = self.unavailable_windows.iterator(.forward);
    while (unavailable_window_iterator.next()) |unavailable_window| unavailable_window.destroy();
    var output_iterator = self.outputs.iterator(.forward);
    while (output_iterator.next()) |output| output.destroy();
    var input_device_iterator = self.inputs.iterator(.forward);
    while (input_device_iterator.next()) |input_device| input_device.destroy();

    self.config.deinit(self.allocator);

    if (self.river_xkb_config_name != null) self.river_xkb_config.destroy();
    if (self.river_libinput_config_name != null) self.river_libinput_config.destroy();
    if (self.river_input_manager_name != null) self.river_input_manager.destroy();
    if (self.river_layer_shell_name != null) self.river_layer_shell.destroy();
    if (self.river_xkb_bindings_name != null) self.river_xkb_bindings.destroy();
    if (self.river_window_manager_name != null) self.river_window_manager.destroy();
    if (self.wp_fractional_scale_manager_name != null) self.wp_fractional_scale_manager.destroy();
    if (self.wp_viewporter_name != null) self.wp_viewporter.destroy();
    if (self.wl_shm_name != null) self.wl_shm.destroy();
    if (self.wl_compositor_name != null) self.wl_compositor.destroy();

    self.wl_registry.destroy();
    self.allocator.free(self.river_home);
    self.allocator.free(self.bridge_zon);
    self.allocator.destroy(self);
    fcft.fini();
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
            } else if (std.mem.orderZ(u8, global.interface, river.InputManagerV1.interface.name) == .eq) {
                self.river_input_manager = self.wl_registry.bind(global.name, river.InputManagerV1, 1) catch unreachable;
                self.river_input_manager_name = global.name;
            } else if (std.mem.orderZ(u8, global.interface, river.LibinputConfigV1.interface.name) == .eq) {
                self.river_libinput_config = self.wl_registry.bind(global.name, river.LibinputConfigV1, 1) catch unreachable;
                self.river_libinput_config_name = global.name;
            } else if (std.mem.orderZ(u8, global.interface, river.XkbConfigV1.interface.name) == .eq) {
                self.river_xkb_config = self.wl_registry.bind(global.name, river.XkbConfigV1, 1) catch unreachable;
                self.river_xkb_config_name = global.name;
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
            } else if (global.name == self.river_input_manager_name) {
                log.err("Global object 'river_input_manager' is no longer available.", .{});
                self.running = false;
            } else if (global.name == self.river_libinput_config_name) {
                log.err("Global object 'river_libinput_config' is no longer available.", .{});
                self.running = false;
            } else if (global.name == self.river_xkb_config_name) {
                log.err("Global object 'river_xkb_config' is no longer available.", .{});
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
            const seat = Seat.create(self, data.id);
            self.seats.append(seat);
            seat.pre();
        },
        .window => |data| {
            const window = Window.create(self, data.id);
            self.unavailable_windows.append(window);
        },
        .output => |data| {
            _ = Output.create(self, data.id);
        },
        .manage_start => {
            var unavailable_window_iterator = self.unavailable_windows.iterator(.forward);
            while (unavailable_window_iterator.next()) |unavailable_window| {
                unavailable_window.init();
                unavailable_window.link.remove();
                unavailable_window.link.init();
            }

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
        .session_locked => {
            var seat_iterator = self.seats.iterator(.forward);
            while (seat_iterator.next()) |seat| {
                var binding_iterator = seat.bindings.iterator(.forward);
                while (binding_iterator.next()) |binding| {
                    if (!binding.map.allow_when_locked) binding.switchLocked(true);
                }
            }
        },
        .session_unlocked => {
            var seat_iterator = self.seats.iterator(.forward);
            while (seat_iterator.next()) |seat| {
                seat.focused_updated = true;
                var binding_iterator = seat.bindings.iterator(.forward);
                while (binding_iterator.next()) |binding| {
                    if (!binding.map.allow_when_locked) binding.switchLocked(false);
                }
            }
        },
    }
}

fn river_input_manager_listener(river_input_manager: *river.InputManagerV1, event: river.InputManagerV1.Event, self: *Self) void {
    log.debug("input_manager#{d} received {s} event.", .{ river_input_manager.getId(), @tagName(event) });
    switch (event) {
        .input_device => |data| {
            const input_device = InputDevice.create(self, data.id);
            self.inputs.append(input_device);
        },
        else => {
            log.debug("input_manager#{d} ignored {s} event.", .{ river_input_manager.getId(), @tagName(event) });
        },
    }
}

fn river_libinput_config_listener(river_libinput_config: *river.LibinputConfigV1, event: river.LibinputConfigV1.Event, self: *Self) void {
    log.debug("libinput_config#{d} received {s} event.", .{ river_libinput_config.getId(), @tagName(event) });
    switch (event) {
        .libinput_device => |data| {
            const river_libinput_device = data.id;
            river_libinput_device.setListener(*Self, river_libinput_device_listener, self);
        },
        else => {
            log.debug("libinput_config#{d} ignored {s} event.", .{ river_libinput_config.getId(), @tagName(event) });
        },
    }
}

fn river_libinput_device_listener(river_libinput_device: *river.LibinputDeviceV1, event: river.LibinputDeviceV1.Event, self: *Self) void {
    log.debug("libinput_device#{d} received {s} event.", .{ river_libinput_device.getId(), @tagName(event) });
    switch (event) {
        .input_device => |data| {
            var input_device_iterator = self.inputs.iterator(.forward);
            while (input_device_iterator.next()) |input_device| {
                if (input_device.river_input_device == data.device) {
                    input_device.river_libinput_device = river_libinput_device;
                    input_device.updateLibinput();
                    break;
                }
            }
        },
        else => {
            log.debug("libinput_device#{d} ignored {s} event.", .{ river_libinput_device.getId(), @tagName(event) });
        },
    }
}

fn river_xkb_config_listener(river_xkb_config: *river.XkbConfigV1, event: river.XkbConfigV1.Event, self: *Self) void {
    log.debug("xkb_config#{d} received {s} event.", .{ river_xkb_config.getId(), @tagName(event) });
    switch (event) {
        .xkb_keyboard => |data| {
            const river_xkb_keyboard = data.id;
            river_xkb_keyboard.setListener(*Self, river_xkb_keyboard_listener, self);
        },
        else => {
            log.debug("xkb_config#{d} ignored {s} event.", .{ river_xkb_config.getId(), @tagName(event) });
        },
    }
}

fn river_xkb_keyboard_listener(river_xkb_keyboard: *river.XkbKeyboardV1, event: river.XkbKeyboardV1.Event, self: *Self) void {
    log.debug("xkb_keyboard#{d} received {s} event.", .{ river_xkb_keyboard.getId(), @tagName(event) });
    switch (event) {
        .input_device => |data| {
            var input_device_iterator = self.inputs.iterator(.forward);
            while (input_device_iterator.next()) |input_device| {
                if (input_device.river_input_device == data.device) {
                    input_device.river_xkb_keyboard = river_xkb_keyboard;
                    input_device.updateXkb();
                    break;
                }
            }
        },
        else => {
            log.debug("xkb_keyboard#{d} ignored {s} event.", .{ river_xkb_keyboard.getId(), @tagName(event) });
        },
    }
}

pub fn reloadConfig(self: *Self) void {
    const old_config = self.config;
    defer old_config.deinit(self.allocator);
    self.config = Config.init(self.allocator, self.bridge_zon);
    self.update();
}

pub fn update(self: *Self) void {
    const bar_font = if (self.config.bar_font) |bar_font| bar_font else Config.default.bar_font.?;
    const font = util.getFont(bar_font.ptr, 120);
    defer font.destroy();
    self.bar_height = @intCast(font.height);

    Window.border_normal = util.getColor(if (self.config.color_selection) |color_selection| color_selection else Config.default.color_selection.?);
    Window.border_focused = util.getColor(if (self.config.color_theme) |color_theme| color_theme else Config.default.color_theme.?);
    Window.border_sticky = util.getColor(if (self.config.color_foreground) |color_foreground| color_foreground else Config.default.color_foreground.?);

    Bar.bar_background = util.getPixmanColor(if (self.config.color_background) |color_background| color_background else Config.default.color_background.?);
    Bar.bar_foreground = util.getPixmanColor(if (self.config.color_foreground) |color_foreground| color_foreground else Config.default.color_foreground.?);
    Bar.bar_selection = util.getPixmanColor(if (self.config.color_selection) |color_selection| color_selection else Config.default.color_selection.?);
    Bar.bar_theme = util.getPixmanColor(if (self.config.color_theme) |color_theme| color_theme else Config.default.color_theme.?);

    var seat_iterator = self.seats.iterator(.forward);
    while (seat_iterator.next()) |seat| seat.changeConfig(self.config);
    var window_iterator = self.windows.iterator(.forward);
    while (window_iterator.next()) |window| window.changeConfig(self.config);
    var output_iterator = self.outputs.iterator(.forward);
    while (output_iterator.next()) |output| output.changeConfig(self.config);
    var input_iterator = self.inputs.iterator(.forward);
    while (input_iterator.next()) |input| input.changeConfig(self.config);
}

pub fn format(_: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("window_manager", .{});
}
