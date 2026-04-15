const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");
const wayland = @import("wayland");
const wl = wayland.client.wl;

const util = @import("util.zig");
const log = util.log;
const WindowManager = @import("WindowManager.zig");

pub fn main() void {
    const wl_display = wl.Display.connect(null) catch {
        log.err("Failed to connect to wayland display.", .{});
        return;
    };
    defer wl_display.disconnect();

    const window_manager = if (builtin.mode == .Debug) blk: {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer if (gpa.deinit() != .ok) unreachable;
        break :blk WindowManager.create(gpa.allocator(), wl_display);
    } else WindowManager.create(std.heap.c_allocator, wl_display);
    defer window_manager.destroy();

    const wl_fd = wl_display.getFd();
    defer posix.close(wl_fd);

    var mask = posix.sigemptyset();
    posix.sigaddset(&mask, posix.SIG.TERM);
    posix.sigprocmask(posix.SIG.BLOCK, &mask, null);
    const sig_fd = posix.signalfd(-1, &mask, @as(u32, @bitCast(posix.O{ .CLOEXEC = true }))) catch unreachable;
    defer posix.close(sig_fd);

    var pollfds = [2]posix.pollfd{
        .{
            .fd = wl_fd,
            .events = posix.POLL.IN,
            .revents = 0,
        },
        .{
            .fd = sig_fd,
            .events = posix.POLL.IN,
            .revents = 0,
        },
    };

    window_manager.startup();

    while (window_manager.running) {
        if (wl_display.flush() != .SUCCESS) unreachable;
        _ = posix.poll(&pollfds, -1) catch unreachable;

        if (pollfds[0].revents & posix.POLL.IN != 0) {
            if (wl_display.dispatch() != .SUCCESS) unreachable;
        }

        if (pollfds[1].revents & posix.POLL.IN != 0) {
            window_manager.running = false;
        }
    }
}
