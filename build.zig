const std = @import("std");

pub fn build(binary: *std.Build) void {
    const target = binary.standardTargetOptions(.{});
    const optimize = binary.standardOptimizeOption(.{});

    const lib = binary.addStaticLibrary(.{
        .name = "liacas",
        .root_source_file = binary.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    binary.installArtifact(lib);

    const exe = binary.addExecutable(.{
        .name = "lia",
        .root_source_file = binary.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    binary.installArtifact(exe);

    const run_cmd = binary.addRunArtifact(exe);
    run_cmd.step.dependOn(binary.getInstallStep());

    if (binary.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = binary.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = binary.addTest(.{
        .root_source_file = binary.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = binary.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = binary.addTest(.{
        .root_source_file = binary.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = binary.addRunArtifact(exe_unit_tests);

    const test_step = binary.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
