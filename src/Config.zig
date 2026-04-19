const std = @import("std");
const util = @import("util.zig");
const pixman = @import("pixman");
const Binding = @import("Binding.zig");

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

map: ?[]const Binding.Mapper = null,

pub const default: Self = @import("bridge.zon");

pub const ConfigW = struct {
    allocator: std.mem.Allocator,
    config: Self = .{},

    pub fn create(allocator: std.mem.Allocator, bridge_zon: []const u8) *ConfigW {
        const configw = allocator.create(ConfigW) catch unreachable;
        configw.* = .{ .allocator = allocator };

        const bridge_zon_data: [:0]const u8 = std.fs.cwd().readFileAllocOptions(allocator, bridge_zon, 1024 * 32, null, .of(u8), 0) catch return configw;
        defer allocator.free(bridge_zon_data);

        @setEvalBranchQuota(2_000_000_000);
        configw.config = std.zon.parse.fromSlice(Self, allocator, bridge_zon_data, null, .{}) catch |err| {
            if (err == error.ParseZon) return configw else unreachable;
        };
        return configw;
    }

    pub fn destroy(self: *ConfigW) void {
        if (self.config.bar_font) |bar_font| self.allocator.free(bar_font);
        if (self.config.bar_placeholder) |bar_placeholder| self.allocator.free(bar_placeholder);
        if (self.config.icon_weight) |icon_weight| for (icon_weight) |item| {
            self.allocator.free(item);
        };
        if (self.config.icon_view) |icon_view| for (icon_view) |item| {
            self.allocator.free(item);
        };
        if (self.config.icon_app_fallback) |icon_app_fallback| self.allocator.free(icon_app_fallback);
        if (self.config.icon_app) |icon_app| {
            for (icon_app) |item| {
                self.allocator.free(item.icon);
                self.allocator.free(item.id);
            }
            self.allocator.free(icon_app);
        }
        if (self.config.cmd_startup) |cmd_startup| {
            for (cmd_startup) |cmd| {
                for (cmd) |part| {
                    self.allocator.free(part);
                }
                self.allocator.free(cmd);
            }
            self.allocator.free(cmd_startup);
        }
        if (self.config.map) |map| {
            for (map) |item| {
                switch (item.action) {
                    .spawn => |cmd| {
                        for (cmd) |part| {
                            self.allocator.free(part);
                        }
                        self.allocator.free(cmd);
                    },
                    else => {},
                }
            }
            self.allocator.free(map);
        }
        self.allocator.destroy(self);
    }
};
