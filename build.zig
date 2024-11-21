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

    // why is this needed? i have no library here?
    // const lib = b.addStaticLibrary(.{
    //     .name = "zig-tictactoe",
    //     // In this case the main source file is merely a path, however, in more
    //     // complicated build scripts, this could be a generated file.
    //     .root_source_file = b.path("src/root.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    // b.installArtifact(lib);

    const exe_cli = b.addExecutable(.{
        .name = "zig-tictactoe-cli",
        .root_source_file = b.path("src/cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_server = b.addExecutable(.{
        .name = "zig-tictactoe-server",
        .root_source_file = b.path("src/server/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const shared_modules = SharedModules.init(b);

    shared_modules.addModulesToExe(&exe_cli.root_module);
    shared_modules.addModulesToExe(&exe_server.root_module);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe_cli);
    b.installArtifact(exe_server);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd_cli = b.addRunArtifact(exe_cli);
    const run_cmd_server = b.addRunArtifact(exe_server);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd_cli.step.dependOn(b.getInstallStep());
    run_cmd_server.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd_cli.addArgs(args);
        run_cmd_server.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step_cli = b.step("cli", "Run the cli app");
    run_step_cli.dependOn(&run_cmd_cli.step);

    const run_step_server = b.step("server", "Run the server");
    run_step_server.dependOn(&run_cmd_server.step);

    // TESTS
    // common tests
    const tests_common = b.addTest(.{
        .root_source_file = b.path("src/common/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    shared_modules.addModulesToExe(&tests_common.root_module);
    const run_tests_common = b.addRunArtifact(tests_common);

    const tests_cli = b.addTest(.{
        .root_source_file = b.path("src/cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    shared_modules.addModulesToExe(&tests_cli.root_module);
    const run_tests_client = b.addRunArtifact(tests_cli);

    const tests_server = b.addTest(.{
        .root_source_file = b.path("src/server/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    shared_modules.addModulesToExe(&tests_server.root_module);
    const run_tests_server = b.addRunArtifact(tests_server);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_tests_common.step);
    test_step.dependOn(&run_tests_client.step);
    test_step.dependOn(&run_tests_server.step);
}

const SharedModules = struct {
    b: *std.Build,
    commonModule: *std.Build.Module,
    uuidModule: *std.Build.Module,
    websocketModule: *std.Build.Module,

    pub fn init(b: *std.Build) SharedModules {
        const uuid_module = b.createModule(.{ .root_source_file = b.path("vendor/uuid/uuid.zig") });
        const websocket_module = b.createModule(.{ .root_source_file = b.path("vendor/websocket/src/websocket.zig") });

        // common depends on vendor...
        // this is quite the pain...
        const common_module = b.createModule(.{
            .root_source_file = b.path("src/common/common.zig"),
        });
        common_module.addImport("uuid", uuid_module);
        common_module.addImport("websocket", websocket_module);

        return .{
            .b = b,
            .commonModule = common_module,
            .uuidModule = uuid_module,
            .websocketModule = websocket_module,
        };
    }

    fn addModulesToExe(self: SharedModules, module: *std.Build.Module) void {
        module.addImport("uuid", self.uuidModule);
        module.addImport("websocket", self.websocketModule);
        module.addImport("common", self.commonModule);
    }
};
