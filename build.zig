const std = @import("std");
const wayland = @import("wayland");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mainModule = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "bridge",
        .root_module = mainModule,
    });
    exe.linkLibC();
    b.installArtifact(exe);

    const waylandScanner = wayland.Scanner.create(b, .{});
    const river = b.dependency("river", .{});
    const wayland_protocols = b.dependency("wayland-protocols", .{});
    waylandScanner.addCustomProtocol(river.path("protocol/river-window-management-v1.xml"));
    waylandScanner.addCustomProtocol(river.path("protocol/river-xkb-bindings-v1.xml"));
    waylandScanner.addCustomProtocol(river.path("protocol/river-layer-shell-v1.xml"));
    waylandScanner.addCustomProtocol(wayland_protocols.path("stable/viewporter/viewporter.xml"));
    waylandScanner.addCustomProtocol(wayland_protocols.path("staging/fractional-scale/fractional-scale-v1.xml"));
    waylandScanner.generate("wl_compositor", 3);
    waylandScanner.generate("wl_shm", 1);
    waylandScanner.generate("wp_viewporter", 1);
    waylandScanner.generate("wp_fractional_scale_manager_v1", 1);
    waylandScanner.generate("river_window_manager_v1", 2);
    waylandScanner.generate("river_xkb_bindings_v1", 1);
    waylandScanner.generate("river_layer_shell_v1", 1);
    const waylandModule = b.createModule(.{
        .root_source_file = waylandScanner.result,
    });
    mainModule.addImport("wayland", waylandModule);
    exe.linkSystemLibrary("wayland-client");

    const xkbcommonModule = b.dependency("xkbcommon", .{}).module("xkbcommon");
    mainModule.addImport("xkbcommon", xkbcommonModule);
    exe.linkSystemLibrary("xkbcommon");

    const pixmanModule = b.dependency("pixman", .{}).module("pixman");
    mainModule.addImport("pixman", pixmanModule);
    exe.linkSystemLibrary("pixman-1");

    const fcftModule = b.dependency("fcft", .{}).module("fcft");
    mainModule.addImport("fcft", fcftModule);
    exe.linkSystemLibrary("fcft");
}
