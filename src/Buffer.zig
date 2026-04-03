const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const linux = std.os.linux;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const pixman = @import("pixman");

const config = @import("config.zig");
const util = @import("util.zig");
const log = util.log;
const Bar = @import("Bar.zig");
const IconRun = @import("IconRun.zig");

const Self = @This();

bar: *Bar,
width: u31,
height: u31,
link: wl.list.Link = undefined,
wl_buffer: *wl.Buffer = undefined,
image: *pixman.Image = undefined,
data: []align(std.heap.page_size_min) u8 = undefined,
busy: bool = false,

pub fn bind(bar: *Bar) void {
    const width = bar.width;
    const height = bar.height;
    const self = std.heap.c_allocator.create(Self) catch unreachable;
    self.* = .{
        .bar = bar,
        .width = width,
        .height = height,
    };
    self.link.init();
    bar.buffers.append(self);

    const stride = width * 4;
    const size = stride * height;
    const fd = posix.memfd_create("bridge-shm-buffer", linux.MFD.CLOEXEC) catch unreachable;
    defer posix.close(fd);
    posix.ftruncate(fd, size) catch unreachable;
    self.data = posix.mmap(null, @intCast(size), posix.PROT.READ | posix.PROT.WRITE, .{ .TYPE = .SHARED }, fd, 0) catch unreachable;
    const pool = bar.output.window_manager.wl_shm.createPool(fd, size) catch unreachable;
    defer pool.destroy();
    self.wl_buffer = pool.createBuffer(0, width, height, stride, .argb8888) catch unreachable;
    self.wl_buffer.setListener(*Self, wl_buffer_listener, self);
    self.image = pixman.Image.createBitsNoClear(.a8r8g8b8, width, height, @as([*c]u32, @ptrCast(self.data.ptr)), stride).?;

    log.debug("{f} has been created.", .{self});
}

pub fn destroy(self: *Self) void {
    log.debug("{f} is about to be destroyed.", .{self});

    self.link.remove();
    _ = self.image.unref();
    self.wl_buffer.destroy();
    posix.munmap(self.data);
    std.heap.c_allocator.destroy(self);
}

fn wl_buffer_listener(_: *wl.Buffer, event: wl.Buffer.Event, self: *Self) void {
    log.debug("{f} received {s} event.", .{ self, @tagName(event) });
    switch (event) {
        .release => {
            if (self.width == self.bar.width and self.height == self.bar.height) {
                self.link.remove();
                self.bar.buffers.append(self);
                self.busy = false;
                log.debug("{f} is ready to be reused.", .{self});
            } else {
                self.destroy();
            }
        },
    }
}

pub fn prepare(self: *Self) void {
    _ = pixman.Image.fillRectangles(
        .src,
        self.image,
        &config.bar_background,
        1,
        &[1]pixman.Rectangle16{.{
            .x = 0,
            .y = 0,
            .width = @intCast(self.width),
            .height = @intCast(self.height),
        }},
    );
}

pub fn stamp(self: *Self, icon_run: *IconRun, position: u31, background: ?*const pixman.Color, foreground: *const pixman.Color) u31 {
    if (background) |nonull_background| {
        _ = pixman.Image.fillRectangles(
            .src,
            self.image,
            nonull_background,
            1,
            &[1]pixman.Rectangle16{.{
                .x = @intCast(position),
                .y = 0,
                .width = @intCast(icon_run.width),
                .height = @intCast(self.height),
            }},
        );
    }
    var x = position;
    const foreground_pix = pixman.Image.createSolidFill(foreground).?;
    for (icon_run.run.glyphs, 0..icon_run.run.count) |glyph, _| {
        if (glyph.is_color_glyph) {
            pixman.Image.composite32(.over, glyph.pix, null, self.image, 0, 0, 0, 0, x + glyph.x, self.bar.font_base - glyph.y, glyph.width, glyph.height);
        } else {
            pixman.Image.composite32(.over, foreground_pix, glyph.pix, self.image, 0, 0, 0, 0, x + glyph.x, self.bar.font_base - glyph.y, glyph.width, glyph.height);
        }
        x += @intCast(glyph.advance.x);
    }
    _ = foreground_pix.unref();
    return x;
}

pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("buffer#{d}", .{self.wl_buffer.getId()});
}
