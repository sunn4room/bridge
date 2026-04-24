const std = @import("std");
const posix = std.posix;
const fcft = @import("fcft");
const pixman = @import("pixman");

pub const log = std.log.scoped(.bridge);

pub const POLLFDS_NUM = 3;

pub fn getEnv(allocator: std.mem.Allocator, name: []const u8) ?[]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |err| {
        if (err == error.EnvironmentVariableNotFound) {
            return null;
        } else unreachable;
    };
}

pub const Color = struct {
    r: u32,
    g: u32,
    b: u32,
    a: u32,
};

pub fn getColor(u: u32) Color {
    return .{
        .r = ((u >> 24) & 0xff) * 0x01010101,
        .g = ((u >> 16) & 0xff) * 0x01010101,
        .b = ((u >> 8) & 0xff) * 0x01010101,
        .a = (u & 0xff) * 0x01010101,
    };
}

pub fn getPixmanColor(u: u32) pixman.Color {
    return .{
        .red = @intCast(((u >> 24) & 0xff) * 0x0101),
        .green = @intCast(((u >> 16) & 0xff) * 0x0101),
        .blue = @intCast(((u >> 8) & 0xff) * 0x0101),
        .alpha = @intCast((u & 0xff) * 0x0101),
    };
}

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn hit(rect: *const Rect, x: i32, y: i32) bool {
        if (x >= rect.x and y >= rect.y and x <= rect.x + rect.w and y <= rect.y + rect.h) {
            return true;
        } else {
            return false;
        }
    }

    pub fn overlay(rect1: *const Rect, rect2: *const Rect) bool {
        if (rect1.x >= rect2.x + rect2.w) return false;
        if (rect2.x >= rect1.x + rect1.w) return false;
        if (rect1.y >= rect2.y + rect2.h) return false;
        if (rect2.y >= rect1.y + rect1.h) return false;
        return true;
    }

    pub fn contain(rect1: *const Rect, rect2: *const Rect) bool {
        if (rect1.x > rect2.x) return false;
        if (rect1.x + rect1.w < rect2.x + rect2.w) return false;
        if (rect1.y > rect2.y) return false;
        if (rect1.y + rect1.h < rect2.y + rect2.h) return false;
        return true;
    }
};

pub fn prepareSpawn() void {
    const sig_ign = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.CHLD, &sig_ign, null);
}

pub fn spawn(cmd: []const []const u8) void {
    if (cmd.len == 0) return;
    if (cmd[0].len == 0) return;

    if (posix.fork() catch unreachable == 0) {
        _ = posix.setsid() catch unreachable;

        var fd: i32 = 3;
        while (fd < 3 + POLLFDS_NUM) : (fd += 1) {
            _ = std.os.linux.close(fd);
        }

        const dev_null_fd = posix.openZ("/dev/null", .{ .ACCMODE = .RDWR }, 0) catch unreachable;
        _ = posix.dup2(dev_null_fd, posix.STDOUT_FILENO) catch unreachable;
        _ = posix.dup2(dev_null_fd, posix.STDERR_FILENO) catch unreachable;

        const sig_dfl = std.posix.Sigaction{
            .handler = .{ .handler = std.posix.SIG.DFL },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.CHLD, &sig_dfl, null);

        if (std.posix.fork() catch unreachable == 0) {
            const argv_buf = std.heap.c_allocator.allocSentinel(?[*:0]const u8, cmd.len, null) catch unreachable;
            for (cmd, 0..) |arg, i| argv_buf[i] = (std.heap.c_allocator.dupeZ(u8, arg) catch unreachable).ptr;
            std.posix.execvpeZ(argv_buf[0].?, argv_buf, std.c.environ) catch {};
            std.posix.exit(1);
        }
        std.posix.exit(0);
    }
}

pub fn getFont(name: [*:0]const u8, dpi: i32) *fcft.Font {
    var names: [1][*:0]const u8 = .{name};
    const names_len: usize = 1;
    if (dpi > 999) unreachable;
    if (dpi < 0) unreachable;
    var attributes = [_]u8{0} ** 8;
    return fcft.Font.fromName(names[0..names_len], std.fmt.bufPrintZ(&attributes, "dpi={}", .{dpi}) catch unreachable) catch unreachable;
}
