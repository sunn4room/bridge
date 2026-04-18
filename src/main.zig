const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const builtin = @import("builtin");
const wayland = @import("wayland");
const wl = wayland.client.wl;

const util = @import("util.zig");
const log = util.log;
const WindowManager = @import("WindowManager.zig");

pub fn main() !void {
    const wl_display = wl.Display.connect(null) catch {
        log.err("Failed to connect to wayland display.", .{});
        return;
    };
    defer wl_display.disconnect();

    var debug_allocator_or_null: ?std.heap.DebugAllocator(.{}) = if (builtin.mode == .Debug) .init else null;
    defer if (debug_allocator_or_null) |*debug_allocator| {
        if (debug_allocator.deinit() != .ok) unreachable;
    };
    const allocator = if (debug_allocator_or_null) |*debug_allocator| debug_allocator.allocator() else std.heap.c_allocator;
    const window_manager = WindowManager.create(allocator, wl_display);
    defer window_manager.destroy();

    var mask = posix.sigemptyset();
    posix.sigaddset(&mask, posix.SIG.TERM);
    posix.sigprocmask(posix.SIG.BLOCK, &mask, null);
    const sig_fd: i32 = posix.signalfd(-1, &mask, 0) catch unreachable;
    defer posix.close(sig_fd);

    const wl_fd: i32 = @intCast(wl_display.getFd());
    defer posix.close(wl_fd);

    const ntf_fd: i32 = @intCast(linux.inotify_init1(0));
    _ = linux.inotify_add_watch(ntf_fd, window_manager.river_home, linux.IN.CLOSE_WRITE | linux.IN.MOVED_TO);
    defer posix.close(ntf_fd);

    var pollfds = [3]posix.pollfd{
        .{
            .fd = sig_fd,
            .events = posix.POLL.IN,
            .revents = 0,
        },
        .{
            .fd = wl_fd,
            .events = posix.POLL.IN,
            .revents = 0,
        },
        .{
            .fd = ntf_fd,
            .events = posix.POLL.IN,
            .revents = 0,
        },
    };

    window_manager.startup();

    while (window_manager.running) {
        if (wl_display.flush() != .SUCCESS) unreachable;
        _ = posix.poll(&pollfds, -1) catch unreachable;

        if (pollfds[0].revents & posix.POLL.IN != 0) {
            window_manager.running = false;
            continue;
        }

        if (pollfds[1].revents & posix.POLL.IN != 0) {
            if (wl_display.dispatch() != .SUCCESS) unreachable;
        }

        if (pollfds[2].revents & posix.POLL.IN != 0) {
            var buffer: [1024]u8 = undefined;
            const read = try posix.read(ntf_fd, &buffer);

            var offset: usize = 0;
            while (offset < read) {
                const event_size = @sizeOf(linux.inotify_event);
                const event: *linux.inotify_event = @ptrCast(@alignCast(buffer[offset .. offset + event_size]));
                if (event.getName()) |name| {
                    if (std.mem.orderZ(u8, name, "bridge.zon") == .eq) {
                        window_manager.reloadConfig();
                        window_manager.river_window_manager.manageDirty();
                    }
                }
                offset += @sizeOf(linux.inotify_event) + event.len;
            }
        }
    }
}
