const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const Self = @This();

color_background: ?u32 = null,
color_foreground: ?u32 = null,
color_selection: ?u32 = null,
color_theme: ?u32 = null,

border_gap: ?i32 = null,
border_width: ?i32 = null,

bar_font: ?[:0]const u8 = null,
bar_placeholder: ?[:0]const u8 = null,

icon_weight: ?[10][:0]const u8 = null,
icon_view: ?[10][:0]const u8 = null,
icon_app_fallback: ?[:0]const u8 = null,
icon_app: ?[]const struct { id: [:0]const u8, icon: [:0]const u8 } = null,

cmd_startup: ?[]const []const []const u8 = null,

map: ?[]const Map = null,

input: ?[]const Input = null,

pub const Map = struct {
    modifiers: river.SeatV1.Modifiers,
    trigger: union(enum) {
        keysym: [:0]const u8,
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

pub const Input = struct {
    type: ?[]const river.InputDeviceV1.Type = null,
    name: ?union(enum) {
        exact: []const []const u8,
        words: []const []const []const u8,
    } = null,
    seat: ?[:0]const u8 = null,
    repeat_info: ?struct {
        rate: i32,
        delay: i32,
    } = null,
    scroll_factor: ?f64 = null,
    map_to: ?struct {
        x: i32,
        y: i32,
        width: i32,
        height: i32,
    } = null,
    libinput: ?struct {
        send_events: ?river.LibinputDeviceV1.SendEventsModes = null,
        tap: ?river.LibinputDeviceV1.TapState = null,
        tap_button_map: ?river.LibinputDeviceV1.TapButtonMap = null,
        drag: ?river.LibinputDeviceV1.DragState = null,
        drag_lock: ?river.LibinputDeviceV1.DragLockState = null,
        three_finger_drag: ?river.LibinputDeviceV1.ThreeFingerDragState = null,
        calibration_matrix: ?[6]f64 = null,
        accel_profile: ?river.LibinputDeviceV1.AccelProfile = null,
        accel_speed: ?f64 = null,
        natural_scroll: ?river.LibinputDeviceV1.NaturalScrollState = null,
        left_handed: ?river.LibinputDeviceV1.LeftHandedState = null,
        click_method: ?river.LibinputDeviceV1.ClickMethod = null,
        clickfinger_button_map: ?river.LibinputDeviceV1.ClickfingerButtonMap = null,
        middle_emulation: ?river.LibinputDeviceV1.MiddleEmulationState = null,
        scroll_method: ?river.LibinputDeviceV1.ScrollMethod = null,
        scroll_button: ?u32 = null,
        scroll_button_lock: ?river.LibinputDeviceV1.ScrollButtonLockState = null,
        dwt: ?river.LibinputDeviceV1.DwtState = null,
        dwtp: ?river.LibinputDeviceV1.DwtpState = null,
        rotation: ?u32 = null,
    } = null,
    xkb: ?struct {
        layout: ?[:0]const u8 = null,
        capslock_enabled: ?bool = null,
        numlock_enabled: ?bool = null,
        keymap: ?struct {
            rules: ?[:0]const u8 = null,
            model: ?[:0]const u8 = null,
            layout: ?[:0]const u8 = null,
            variant: ?[:0]const u8 = null,
            options: ?[:0]const u8 = null,
        } = null,
    } = null,
};

pub fn init(allocator: std.mem.Allocator, bridge_zon: []const u8) *const Self {
    const config = allocator.create(Self) catch unreachable;
    config.* = .{};

    const bridge_zon_data: [:0]const u8 = std.fs.cwd().readFileAllocOptions(allocator, bridge_zon, 1024 * 32, null, .of(u8), 0) catch return config;
    defer allocator.free(bridge_zon_data);

    @setEvalBranchQuota(2_000_000_000);
    config.* = std.zon.parse.fromSlice(Self, allocator, bridge_zon_data, null, .{}) catch |err| {
        if (err == error.ParseZon) return config else unreachable;
    };
    return config;
}

pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
    if (self.bar_font) |bar_font| allocator.free(bar_font);
    if (self.bar_placeholder) |bar_placeholder| allocator.free(bar_placeholder);
    if (self.icon_weight) |icon_weight| for (icon_weight) |item| {
        allocator.free(item);
    };
    if (self.icon_view) |icon_view| for (icon_view) |item| {
        allocator.free(item);
    };
    if (self.icon_app_fallback) |icon_app_fallback| allocator.free(icon_app_fallback);
    if (self.icon_app) |icon_app| {
        for (icon_app) |item| {
            allocator.free(item.icon);
            allocator.free(item.id);
        }
        allocator.free(icon_app);
    }
    if (self.cmd_startup) |cmd_startup| {
        for (cmd_startup) |cmd| {
            for (cmd) |part| {
                allocator.free(part);
            }
            allocator.free(cmd);
        }
        allocator.free(cmd_startup);
    }
    if (self.map) |map| {
        for (map) |item| {
            switch (item.trigger) {
                .keysym => |key| {
                    allocator.free(key);
                },
                else => {},
            }
            switch (item.action) {
                .spawn => |cmd| {
                    for (cmd) |part| {
                        allocator.free(part);
                    }
                    allocator.free(cmd);
                },
                else => {},
            }
        }
        allocator.free(map);
    }
    if (self.input) |input| {
        for (input) |item| {
            if (item.type) |@"type"| {
                allocator.free(@"type");
            }
            if (item.name) |name| {
                switch (name) {
                    .exact => |exact| {
                        for (exact) |each_exact| {
                            allocator.free(each_exact);
                        }
                        allocator.free(exact);
                    },
                    .words => |words| {
                        for (words) |each_words| {
                            for (each_words) |word| {
                                allocator.free(word);
                            }
                            allocator.free(each_words);
                        }
                        allocator.free(words);
                    },
                }
            }
            if (item.seat) |seat| {
                allocator.free(seat);
            }
            if (item.xkb) |xkb| {
                if (xkb.layout) |layout| {
                    allocator.free(layout);
                }
                if (xkb.keymap) |keymap| {
                    if (keymap.rules) |rules| allocator.free(rules);
                    if (keymap.model) |model| allocator.free(model);
                    if (keymap.layout) |layout| allocator.free(layout);
                    if (keymap.variant) |variant| allocator.free(variant);
                    if (keymap.options) |options| allocator.free(options);
                }
            }
        }
        allocator.free(input);
    }
    allocator.destroy(self);
}

pub const default: Self = @import("bridge.zon");
