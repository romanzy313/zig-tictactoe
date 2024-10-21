const std = @import("std");
const testing = std.testing;
const ArenaAllocator = std.heap.ArenaAllocator;

// this test always fails on purpose
// test "Arena fubfree" {
//     const testing_allocator = testing.allocator;

//     var area_allocator = ArenaAllocator.init(testing_allocator);
//     defer area_allocator.deinit();
//     const alloc = area_allocator.allocator();

//     const obj = try alloc.alloc(struct { x: f32 }, 1);
//     // this works:
//     // defer alloc.free(obj);
//     // but this panics: try to clear with the original allocator instead
//     try testing.expectError(error.WillPanic, testing_allocator.free(obj));
// }
