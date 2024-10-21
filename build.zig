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

    const exe_client = b.addExecutable(.{
        .name = "zig-tictactoe-client",
        .root_source_file = b.path("src/client/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_server = b.addExecutable(.{
        .name = "zig-tictactoe-server",
        .root_source_file = b.path("src/server/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const vendor_module = b.createModule(.{ .root_source_file = b.path("vendor/vendor.zig") });

    // common depends on vendor...
    // this is quite the pain...
    const common_module = b.createModule(.{
        .root_source_file = b.path("src/common/common.zig"),
    });
    common_module.addImport("vendor", vendor_module);

    const shared_modules = SharedModules{
        .b = b,
        .vendorModule = vendor_module,
        .commonModule = common_module,
    };

    // before:
    // exe_client.root_module.addImport("vendor", vendor_module);
    // exe_client.root_module.addImport("common", common_module);
    // exe_server.root_module.addImport("vendor", vendor_module);
    // exe_server.root_module.addImport("common", common_module);

    // after:
    shared_modules.addModulesToExe(&exe_client.root_module);
    shared_modules.addModulesToExe(&exe_server.root_module);

    // external dependencies
    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
        .openssl = false, // set to true to enable TLS support
    });

    exe_server.root_module.addImport("zap", zap.module("zap"));

    // exe_server.addObject("src/ai.zig");

    // const mp_module = b.addModule(
    //     "ai",
    //     .{
    //         .
    //         //.{ .path = b.pathJoin(&.{ "src", "ai.zig" }) },
    //     },
    // );
    // exe_server.root_module.addImport("ai", mp_module);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe_client);
    b.installArtifact(exe_server);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd_client = b.addRunArtifact(exe_client);
    const run_cmd_server = b.addRunArtifact(exe_server);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd_client.step.dependOn(b.getInstallStep());
    run_cmd_server.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd_client.addArgs(args);
        run_cmd_server.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step_client = b.step("client", "Run the app");
    run_step_client.dependOn(&run_cmd_client.step);

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

    const tests_client = b.addTest(.{
        .root_source_file = b.path("src/client/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    shared_modules.addModulesToExe(&tests_client.root_module);
    const run_tests_client = b.addRunArtifact(tests_client);

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
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests_common.step);
    test_step.dependOn(&run_tests_client.step);
    test_step.dependOn(&run_tests_server.step);

    // OLD
    // there is a separate lib and "executable tests..."

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    // Unit tests are the same for client and server!
    // const lib_unit_tests = b.addTest(.{
    //     .root_source_file = b.path("src/root.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // const exe_unit_tests_client = b.addTest(.{
    //     .root_source_file = b.path("src/client/main.zig"), // FIXME: what should be done here?
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const run_exe_unit_tests_client = b.addRunArtifact(exe_unit_tests_client);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_lib_unit_tests.step);
    // test_step.dependOn(&run_exe_unit_tests_client.step);
}

const SharedModules = struct {
    b: *std.Build,
    vendorModule: *std.Build.Module,
    commonModule: *std.Build.Module,

    fn addModulesToExe(self: SharedModules, module: *std.Build.Module) void {
        module.addImport("vendor", self.vendorModule);
        module.addImport("common", self.commonModule);
    }
};
