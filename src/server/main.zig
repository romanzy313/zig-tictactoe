const std = @import("std");
const zap = @import("zap");
const debug = std.debug;

const Routes = @import("Routes.zig");
const GameRepo = @import("game_repo.zig").GameRepo;

fn on_request_verbose(r: zap.Request) void {
    if (r.path) |the_path| {
        std.debug.print("PATH: {s}\n", .{the_path});
    }

    if (r.query) |the_query| {
        std.debug.print("QUERY: {s}\n", .{the_query});
    }
    r.sendBody("<html><body><h1>Hello from ZAP!!!</h1></body></html>") catch return;
}

fn not_found(req: zap.Request) void {
    std.debug.print("not found handler", .{});

    req.sendBody("Not found") catch return;
}

// Lets figure out the http server
// maybe make this websocket only?
// or try the manual way of doing polling?
pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{
    //     .thread_safe = true,
    // }){};

    // defer {
    //     const check = gpa.deinit();

    //     if (check == .leak) {
    //         debug.print("THERE WAS A LEAK !!!1!\n", .{});
    //     }
    // }

    // const allocator = gpa.allocator();

    // var simple_router = zap.Router.init(allocator, .{
    //     .not_found = not_found,
    // });
    // defer simple_router.deinit();

    // var game_repo = GameRepo.init(allocator);
    // defer game_repo.deinit();

    // var routes = Routes.init(allocator, &game_repo, "localhost:3000");

    // try simple_router.handle_func("/api/new-game", &routes, &Routes.newGame);
    // try simple_router.handle_func("/api/game", &routes, &Routes.getGame);
    // try simple_router.handle_func("/api/all-games", &routes, &Routes.getAllGames);

    // var listener = zap.HttpListener.init(.{
    //     .port = 3000,
    //     .on_request = simple_router.on_request_handler(),
    //     .log = true,
    //     .max_clients = 100000,
    // });
    // try listener.listen();

    // std.debug.print("Listening on 0.0.0.0:3000\n", .{});

    // // start worker threads
    // zap.start(.{
    //     .threads = 1,
    //     .workers = 1,
    // });
}

test {
    _ = @import("game_repo.zig");
}
