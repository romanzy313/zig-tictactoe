// coerse types
// @as([]const u8, "zz");

// function initialization (at comptime)
// pub fn init(pointer: anytype, comptime fillFn: fn (ptr: @TypeOf(pointer), buf: []u8) void) Random {

// better example
// pub fn sort(
//     comptime T: type,
//     items: []T,
//     context: anytype,
//     comptime lessThanFn: fn (@TypeOf(context), lhs: T, rhs: T) bool,
// ) void {
//     std.sort.block(T, items, context, lessThanFn);
// }

// initialize 1d array of fixed size at comptime
// comptime var routes = [_]RoutePart{.{
//     .empty = {},
// }} ** maxDepth;

// make 2d array of fixed size at comptime
// const mat3x2 = [_][2]u32{
//     [_]u32{ 1, 2 },
//     [_]u32{ 3, 4 },
//     [_]u32{ 5, 6 },
// };
