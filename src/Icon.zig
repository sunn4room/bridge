const std = @import("std");
const unicode = std.unicode;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const fcft = @import("fcft");

const util = @import("util.zig");
const log = util.log;
const Bar = @import("Bar.zig");

const Self = @This();

allocator: std.mem.Allocator,
bar: *Bar,
key: [*:0]const u8,
link: wl.list.Link = undefined,
run: *const fcft.TextRun = undefined,
width: i32 = 0,

pub fn create(bar: *Bar, key: [*:0]const u8) *Self {
    const self = bar.allocator.create(Self) catch unreachable;
    self.* = .{
        .allocator = bar.allocator,
        .bar = bar,
        .key = key,
    };
    self.link.init();

    const icon_slice: []const u8 = std.mem.span(key);
    var codepoint_iterator = (unicode.Utf8View.init(icon_slice) catch unreachable).iterator();
    const codepoint_count = unicode.utf8CountCodepoints(icon_slice) catch unreachable;
    const codepoints: []u32 = self.allocator.alloc(u32, codepoint_count) catch unreachable;
    defer self.allocator.free(codepoints);
    var i: usize = 0;
    while (codepoint_iterator.nextCodepoint()) |cp| : (i += 1) codepoints[i] = cp;
    self.run = bar.font.rasterizeTextRunUtf32(codepoints, .default) catch unreachable;
    for (self.run.glyphs, 0..self.run.count) |glyph, _| self.width += @intCast(glyph.advance.x);

    log.debug("{f} has been created.", .{self});
    return self;
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    self.link.remove();
    self.run.destroy();
    self.allocator.destroy(self);
}

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("icon(\"{s}\")#{d}", .{ self.key, self.bar.output.river_output.getId() });
}
