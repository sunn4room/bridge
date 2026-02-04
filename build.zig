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
    waylandScanner.addCustomProtocol(river.path("protocol/river-window-management-v1.xml"));
    waylandScanner.addCustomProtocol(river.path("protocol/river-xkb-bindings-v1.xml"));
    waylandScanner.addCustomProtocol(river.path("protocol/river-layer-shell-v1.xml"));
    waylandScanner.generate("river_window_manager_v1", 4);
    waylandScanner.generate("river_xkb_bindings_v1", 2);
    waylandScanner.generate("river_layer_shell_v1", 1);
    const waylandModule = b.createModule(.{
        .root_source_file = waylandScanner.result,
    });
    mainModule.addImport("wayland", waylandModule);
    exe.linkSystemLibrary("wayland-client");

    const xkbcommonModule = b.dependency("xkbcommon", .{}).module("xkbcommon");
    mainModule.addImport("xkbcommon", xkbcommonModule);
    exe.linkSystemLibrary("xkbcommon");
}
