const std = @import("std");
// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const vendor_modules = ModuleGroup{
        .b = b,
        .definitions = &[_]ModuleGroup.Definition{
            .{ .name = "uuid", .module = b.createModule(.{ .root_source_file = b.path("vendor/uuid/uuid.zig") }) },
            .{ .name = "websocket", .module = b.createModule(.{ .root_source_file = b.path("vendor/websocket/src/websocket.zig") }) },
        },
    };

    // app goes first
    const exe_app = b.addExecutable(.{
        .name = "zig-tictactoe-app",
        .root_source_file = b.path("src/main_app.zig"),
        .target = target,
        .optimize = optimize,
    });

    vendor_modules.addModulesToExe(&exe_app.root_module);

    // https://github.com/Not-Nik/raylib-zig
    const raylib_dep = b.dependency("raylib-zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    exe_app.linkLibrary(raylib_artifact);
    exe_app.root_module.addImport("raylib", raylib);
    exe_app.root_module.addImport("raygui", raygui);

    const exe_server = b.addExecutable(.{
        .name = "zig-tictactoe-server",
        .root_source_file = b.path("src/main_server.zig"),
        .target = target,
        .optimize = optimize,
    });

    vendor_modules.addModulesToExe(&exe_server.root_module);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe_app);
    b.installArtifact(exe_server);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd_app = b.addRunArtifact(exe_app);
    const run_cmd_server = b.addRunArtifact(exe_server);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd_app.step.dependOn(b.getInstallStep());
    run_cmd_server.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd_app.addArgs(args);
        run_cmd_server.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step_cli = b.step("app", "Run the app");
    run_step_cli.dependOn(&run_cmd_app.step);

    const run_step_server = b.step("server", "Run the server");
    run_step_server.dependOn(&run_cmd_server.step);

    // TESTS are always in root?
    const tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    vendor_modules.addModulesToExe(&tests.root_module);
    const run_tests = b.addRunArtifact(tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_tests.step);
}

const ModuleGroup = struct {
    pub const Definition = struct {
        name: []const u8,
        module: *std.Build.Module,
    };

    b: *std.Build,
    definitions: []const Definition,

    fn addModulesToExe(self: ModuleGroup, module: *std.Build.Module) void {
        for (self.definitions) |def| {
            module.addImport(def.name, def.module);
        }
    }
};
