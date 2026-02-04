const std = @import("std");

pub const RuntimeBackend = enum {
    none,
    gtk,
    swift,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const default_runtime: RuntimeBackend = if (target.result.os.tag == .macos) .swift else .none;
    const runtime = b.option(RuntimeBackend, "runtime", "App runtime backend") orelse default_runtime;

    const build_config = b.addOptions();
    build_config.addOption(RuntimeBackend, "runtime", runtime);

    const lib = b.addLibrary(.{
        .name = "colony_core",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "build_config", .module = build_config.createModule() },
            },
        }),
        .linkage = .static,
    });

    lib.bundle_compiler_rt = true;
    lib.linkSystemLibrary("sqlite3");

    b.installArtifact(lib);

    const lib_header = b.addInstallHeaderFile(
        b.path("src/include/colony.h"),
        "colony.h",
    );
    b.getInstallStep().dependOn(&lib_header.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "build_config", .module = build_config.createModule() },
            },
        }),
    });
    unit_tests.linkSystemLibrary("sqlite3");

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const run_step = b.step("run", "Build and run the Swift app");
    if (runtime == .swift) {
        const swift_build = b.addSystemCommand(&.{
            "swift", "build", "--package-path", "macos",
        });
        swift_build.step.dependOn(b.getInstallStep());

        const swift_exec = b.addSystemCommand(&.{
            "macos/.build/debug/Colony",
        });
        swift_exec.step.dependOn(&swift_build.step);
        run_step.dependOn(&swift_exec.step);
    } else {
        const run_msg = b.addSystemCommand(&.{ "echo", "Swift runtime only available on macOS" });
        run_step.dependOn(&run_msg.step);
    }
}
