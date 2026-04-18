const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;
const xkbcommon = @import("xkbcommon");

const Config = @import("Config.zig");
const util = @import("util.zig");
const log = util.log;
const WindowManager = @import("WindowManager.zig");

const Self = @This();

allocator: std.mem.Allocator,
window_manager: *WindowManager,
river_input_device: *river.InputDeviceV1,
river_libinput_device: ?*river.LibinputDeviceV1 = null,
river_xkb_keyboard: ?*river.XkbKeyboardV1 = null,
link: wl.list.Link = undefined,
config: *const Config = undefined,
name: []const u8 = undefined,
type: river.InputDeviceV1.Type = undefined,
input: Config.Input = .{},

pub fn create(window_manager: *WindowManager, river_input_device: *river.InputDeviceV1) *Self {
    const self = window_manager.allocator.create(Self) catch unreachable;
    self.* = .{
        .allocator = window_manager.allocator,
        .window_manager = window_manager,
        .river_input_device = river_input_device,
    };

    self.river_input_device.setListener(*Self, river_input_device_listener, self);
    self.link.init();

    log.debug("{f} has been created.", .{self});
    return self;
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    self.link.remove();
    if (self.river_libinput_device) |river_libinput_device| river_libinput_device.destroy();
    if (self.river_xkb_keyboard) |river_xkb_keyboard| river_xkb_keyboard.destroy();
    self.river_input_device.destroy();
    self.allocator.free(self.name);
    self.allocator.destroy(self);
}

fn river_input_device_listener(_: *river.InputDeviceV1, event: river.InputDeviceV1.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .removed => {
            self.destroy();
        },
        .type => |data| {
            self.type = data.type;
            log.debug("{f} type: {s}", .{ self, @tagName(self.type) });
        },
        .name => |data| {
            self.name = self.allocator.dupe(u8, std.mem.span(data.name)) catch unreachable;
            log.debug("{f} name: {s}", .{ self, self.name });
            self.changeConfig(self.window_manager.config);
        },
    }
}

pub fn match(self: *Self, input: *const Config.Input) bool {
    if (input.type) |@"type"| {
        var matched: bool = false;
        for (@"type") |each_type| {
            if (self.type == each_type) {
                matched = true;
                break;
            }
        }
        if (!matched) return false;
    }
    if (input.name) |name| {
        var matched: bool = false;
        switch (name) {
            .exact => |exact| {
                for (exact) |each_exact| {
                    if (std.mem.order(u8, self.name, each_exact) == .eq) {
                        matched = true;
                        break;
                    }
                }
            },
            .words => |keys| {
                for (keys) |each_keys| {
                    var n: []const u8 = self.name;
                    matched = for (each_keys) |key| {
                        if (std.mem.indexOf(u8, n, key)) |index| {
                            n = n[index + key.len .. n.len];
                        } else break false;
                    } else true;
                    if (matched) break;
                }
            },
        }
        if (!matched) return false;
    }
    return true;
}

pub fn changeConfig(self: *Self, config: *const Config) void {
    self.config = config;

    self.input = .{};
    const input = if (self.config.input) |input| input else Config.default.input.?;
    for (input) |*each_input| {
        if (self.match(each_input)) {
            if (each_input.seat) |seat| self.input.seat = seat;
            if (each_input.repeat_info) |repeat_info| self.input.repeat_info = repeat_info;
            if (each_input.scroll_factor) |scroll_factor| self.input.scroll_factor = scroll_factor;
            if (each_input.map_to) |map_to| self.input.map_to = map_to;
            if (each_input.libinput) |libinput| {
                if (self.input.libinput == null) self.input.libinput = .{};

                if (libinput.send_events) |send_events| self.input.libinput.?.send_events = send_events;
                if (libinput.tap) |tap| self.input.libinput.?.tap = tap;
                if (libinput.tap_button_map) |tap_button_map| self.input.libinput.?.tap_button_map = tap_button_map;
                if (libinput.drag) |drag| self.input.libinput.?.drag = drag;
                if (libinput.drag_lock) |drag_lock| self.input.libinput.?.drag_lock = drag_lock;
                if (libinput.three_finger_drag) |three_finger_drag| self.input.libinput.?.three_finger_drag = three_finger_drag;
                if (libinput.calibration_matrix) |calibration_matrix| self.input.libinput.?.calibration_matrix = calibration_matrix;
                if (libinput.accel_profile) |accel_profile| self.input.libinput.?.accel_profile = accel_profile;
                if (libinput.accel_speed) |accel_speed| self.input.libinput.?.accel_speed = accel_speed;
                if (libinput.natural_scroll) |natural_scroll| self.input.libinput.?.natural_scroll = natural_scroll;
                if (libinput.left_handed) |left_handed| self.input.libinput.?.left_handed = left_handed;
                if (libinput.click_method) |click_method| self.input.libinput.?.click_method = click_method;
                if (libinput.clickfinger_button_map) |clickfinger_button_map| self.input.libinput.?.clickfinger_button_map = clickfinger_button_map;
                if (libinput.middle_emulation) |middle_emulation| self.input.libinput.?.middle_emulation = middle_emulation;
                if (libinput.scroll_method) |scroll_method| self.input.libinput.?.scroll_method = scroll_method;
                if (libinput.scroll_button) |scroll_button| self.input.libinput.?.scroll_button = scroll_button;
                if (libinput.scroll_button_lock) |scroll_button_lock| self.input.libinput.?.scroll_button_lock = scroll_button_lock;
                if (libinput.dwt) |dwt| self.input.libinput.?.dwt = dwt;
                if (libinput.dwtp) |dwtp| self.input.libinput.?.dwtp = dwtp;
                if (libinput.rotation) |rotation| self.input.libinput.?.rotation = rotation;
            }
            if (each_input.xkb) |xkb| {
                if (self.input.xkb == null) self.input.xkb = .{};

                if (xkb.layout) |layout| self.input.xkb.?.layout = layout;
                if (xkb.capslock_enabled) |capslock_enabled| self.input.xkb.?.capslock_enabled = capslock_enabled;
                if (xkb.numlock_enabled) |numlock_enabled| self.input.xkb.?.numlock_enabled = numlock_enabled;
                if (xkb.keymap) |keymap| {
                    if (self.input.xkb.?.keymap == null) self.input.xkb.?.keymap = .{};

                    if (keymap.rules) |rules| self.input.xkb.?.keymap.?.rules = rules;
                    if (keymap.model) |model| self.input.xkb.?.keymap.?.model = model;
                    if (keymap.layout) |layout| self.input.xkb.?.keymap.?.layout = layout;
                    if (keymap.variant) |variant| self.input.xkb.?.keymap.?.variant = variant;
                    if (keymap.options) |options| self.input.xkb.?.keymap.?.options = options;
                }
            }
        }
    }

    self.updateInput();
    self.updateLibinput();
    self.updateXkb();
}

pub fn updateInput(self: *Self) void {
    if (self.input.seat) |seat| {
        self.window_manager.river_input_manager.createSeat(seat.ptr);
        self.river_input_device.assignToSeat(seat.ptr);
    }
    if (self.input.repeat_info) |repeat_info| {
        self.river_input_device.setRepeatInfo(repeat_info.rate, repeat_info.delay);
    }
    if (self.input.scroll_factor) |scroll_factor| {
        self.river_input_device.setScrollFactor(.fromDouble(scroll_factor));
    }
    if (self.input.map_to) |map_to| {
        self.river_input_device.mapToRectangle(map_to.x, map_to.y, map_to.width, map_to.height);
    }
}

pub fn updateLibinput(self: *Self) void {
    if (self.river_libinput_device) |river_libinput_device| {
        if (self.input.libinput) |libinput| {
            if (libinput.send_events) |send_events| {
                _ = river_libinput_device.setSendEvents(send_events) catch unreachable;
            }
            if (libinput.tap) |tap| {
                _ = river_libinput_device.setTap(tap) catch unreachable;
            }
            if (libinput.tap_button_map) |tap_button_map| {
                _ = river_libinput_device.setTapButtonMap(tap_button_map) catch unreachable;
            }
            if (libinput.drag) |drag| {
                _ = river_libinput_device.setDrag(drag) catch unreachable;
            }
            if (libinput.drag_lock) |drag_lock| {
                _ = river_libinput_device.setDragLock(drag_lock) catch unreachable;
            }
            if (libinput.three_finger_drag) |three_finger_drag| {
                _ = river_libinput_device.setThreeFingerDrag(three_finger_drag) catch unreachable;
            }
            if (libinput.calibration_matrix) |calibration_matrix| {
                var buffer = calibration_matrix;
                const array_list = std.ArrayList(f64).initBuffer(&buffer);
                var array = wl.Array.fromArrayList(f64, array_list);
                _ = river_libinput_device.setCalibrationMatrix(&array) catch unreachable;
            }
            if (libinput.accel_profile) |accel_profile| {
                _ = river_libinput_device.setAccelProfile(accel_profile) catch unreachable;
            }
            if (libinput.accel_speed) |accel_speed| {
                var buffer = [_]f64{accel_speed};
                const array_list = std.ArrayList(f64).initBuffer(&buffer);
                var array = wl.Array.fromArrayList(f64, array_list);
                _ = river_libinput_device.setAccelSpeed(&array) catch unreachable;
            }
            if (libinput.natural_scroll) |natural_scroll| {
                _ = river_libinput_device.setNaturalScroll(natural_scroll) catch unreachable;
            }
            if (libinput.left_handed) |left_handed| {
                _ = river_libinput_device.setLeftHanded(left_handed) catch unreachable;
            }
            if (libinput.click_method) |click_method| {
                _ = river_libinput_device.setClickMethod(click_method) catch unreachable;
            }
            if (libinput.clickfinger_button_map) |clickfinger_button_map| {
                _ = river_libinput_device.setClickfingerButtonMap(clickfinger_button_map) catch unreachable;
            }
            if (libinput.middle_emulation) |middle_emulation| {
                _ = river_libinput_device.setMiddleEmulation(middle_emulation) catch unreachable;
            }
            if (libinput.scroll_method) |scroll_method| {
                _ = river_libinput_device.setScrollMethod(scroll_method) catch unreachable;
            }
            if (libinput.scroll_button) |scroll_button| {
                _ = river_libinput_device.setScrollButton(scroll_button) catch unreachable;
            }
            if (libinput.scroll_button_lock) |scroll_button_lock| {
                _ = river_libinput_device.setScrollButtonLock(scroll_button_lock) catch unreachable;
            }
            if (libinput.dwt) |dwt| {
                _ = river_libinput_device.setDwt(dwt) catch unreachable;
            }
            if (libinput.dwtp) |dwtp| {
                _ = river_libinput_device.setDwtp(dwtp) catch unreachable;
            }
            if (libinput.rotation) |rotation| {
                _ = river_libinput_device.setRotation(rotation) catch unreachable;
            }
        }
    }
}

pub fn updateXkb(self: *Self) void {
    if (self.river_xkb_keyboard) |river_xkb_keyboard| {
        if (self.input.xkb) |xkb| {
            if (xkb.layout) |layout| {
                river_xkb_keyboard.setLayoutByName(layout);
            }
            if (xkb.capslock_enabled) |capslock_enabled| {
                if (capslock_enabled) {
                    river_xkb_keyboard.capslockEnable();
                } else {
                    river_xkb_keyboard.capslockDisable();
                }
            }
            if (xkb.numlock_enabled) |numlock_enabled| {
                if (numlock_enabled) {
                    river_xkb_keyboard.numlockEnable();
                } else {
                    river_xkb_keyboard.numlockDisable();
                }
            }
            if (xkb.keymap) |keymap| {
                const xkb_context = xkbcommon.Context.new(.no_flags).?;
                defer xkb_context.unref();

                const xkb_rule_names = xkbcommon.RuleNames{
                    .rules = if (keymap.rules) |rules| rules.ptr else null,
                    .model = if (keymap.model) |model| model.ptr else null,
                    .layout = if (keymap.layout) |layout| layout.ptr else null,
                    .variant = if (keymap.variant) |variant| variant.ptr else null,
                    .options = if (keymap.options) |options| options.ptr else null,
                };

                const xkb_keymap = xkbcommon.Keymap.newFromNames2(xkb_context, &xkb_rule_names, .text_v2, .no_flags).?;
                defer xkb_keymap.unref();
                const xkb_keymap_str = xkb_keymap.getAsString2(.text_v2, .{}).?;

                const fd = std.posix.memfd_createZ("bridge-keymap", 0) catch unreachable;
                defer std.posix.close(fd);

                _ = std.posix.write(fd, std.mem.span(xkb_keymap_str)) catch unreachable;

                const river_xkb_keymap = self.window_manager.river_xkb_config.createKeymap(fd, .text_v2) catch unreachable;
                river_xkb_keymap.setListener(*Self, river_xkb_keymap_listener, self);
            }
        }
    }
}

fn river_xkb_keymap_listener(river_xkb_keymap: *river.XkbKeymapV1, event: river.XkbKeymapV1.Event, self: *Self) void {
    log.debug("xkb_keymap#{d} received {s} event.", .{ river_xkb_keymap.getId(), @tagName(event) });
    switch (event) {
        .success => {
            self.river_xkb_keyboard.?.setKeymap(river_xkb_keymap);
        },
        .failure => {},
    }
    river_xkb_keymap.destroy();
}

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("input_device#{d}", .{self.river_input_device.getId()});
}
