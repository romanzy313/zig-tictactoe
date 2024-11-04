// const std = @import("std");
// const json = std.json;
// const zap = @import("zap");
// const Allocator = std.mem.Allocator;

// fn SubType2(comptime T: type) type {
//     return struct {
//         value: T,
//         deinit: *const fn () void,
//     };
// }

// fn SubType(comptime T: type) type {
//     return struct {
//         value: T,
//         deinit: *const fn () void,
//     };
// }

// // this will require a proper inheritence...
// pub fn ParseResult(T: type) type {
//     return struct {
//         ptr: *anyopaque,
//         _deinit: fn (ctx: *anyopaque) void,
//         value: T,

//         const Self = @This();

//         pub fn deinit(self: ParseResult) void {
//             self._deinit(self.ptr);
//         }
//     };
// }

// pub fn JsonParseResult(T: type) type {
//     return struct {
//         parsed: json.Parsed(T),

//         const Self = @This();

//         pub fn initByParsing(allocator: Allocator, body: []const u8) !JsonParseResult(T) {
//             const res = std.json.parseFromSlice(T, allocator, body, .{}) catch {
//                 return error.FailedToParseBody;
//             };
//             return .{
//                 .parsed = res,
//             };
//         }

//         pub fn result(self: *Self) ParseResult(T) {
//             return .{
//                 .ptr = self,
//                 .value = self.parsed.value,
//                 ._deinit = deinit,
//             };
//         }

//         pub fn deinit(ctx: *anyopaque) void {
//             const self: *Self = @ptrCast(@alignCast(ctx));
//             return self.parsed.deinit();
//         }
//     };
// }

// // pub fn typedParseBody(comptime T: type) type {
// //     return struct {
// //         value: T,

// //         _deinit: *fn (ctx: *anyopaque) void,

// //         const Self = @This();

// //         pub fn parse(allocator: Allocator, req: *const zap.Request) !Self {
// //             req.parseBody() catch {
// //                 return error.FailedToParseBody;
// //             };

// //             // huh? how is this []const u8?
// //             if (req.body) |body| {
// //                 const content_type = req.getHeader("content-type");

// //                 if (content_type == null) {
// //                     return error.UnsupportedContentType;
// //                 }

// //                 if (std.mem.startsWith(u8, content_type.?, "application/json")) {
// //                     const val = std.json.parseFromSlice(T, allocator, body, .{}) catch {
// //                         return error.FailedToParseBody;
// //                     };

// //                     return .{
// //                         .value = val.value,
// //                         ._deinit = deinit,
// //                     };
// //                 } else {
// //                     return error.UnsupportedContentType;
// //                 }
// //             }

// //             return error.FailedToParseNoBody;
// //         }

// //         pub fn deinit(self: Self) void {}
// //     };
// // }

// // I cant make this work...
// pub fn parseBody(comptime T: type, allocator: Allocator, req: *const zap.Request) !ParseResult(T) {
//     req.parseBody() catch {
//         return error.FailedToParseBody;
//     };

//     // huh? how is this []const u8?
//     if (req.body) |body| {
//         const content_type = req.getHeader("content-type");

//         if (content_type == null) {
//             return error.UnsupportedContentType;
//         }

//         if (std.mem.startsWith(u8, content_type.?, "application/json")) {
//             var res = try JsonParseResult(T).initByParsing(allocator, body);
//             return res.result();
//         } else {
//             return error.UnsupportedContentType;
//         }
//     }

//     return error.FailedToParseNoBody;
// }
// pub fn parseBodyJson(T: type, allocator: Allocator, req: *const zap.Request, options: json.ParseOptions) !json.Parsed(T) {
//     req.parseBody() catch {
//         return error.FailedToParseBodyStage1;
//     };

//     // huh? how is this []const u8?
//     if (req.body) |body| {
//         const val = std.json.parseFromSlice(T, allocator, body, options) catch {
//             return error.FailedToParseBodyStage3;
//         };
//         return val;
//     }

//     return error.FailedToParseBodyStage2;
// }

// // another failure
// // pub fn parseBody(comptime T: type, allocator: Allocator, req: *const zap.Request) !ParseResult(T) {
// //     req.parseBody() catch {
// //         return error.FailedToParseBody;
// //     };

// //     // huh? how is this []const u8?
// //     if (req.body) |body| {
// //         const content_type = req.getHeader("content-type");

// //         if (content_type == null) {
// //             return error.UnsupportedContentType;
// //         }

// //         if (std.mem.startsWith(u8, content_type.?, "application/json")) {
// //             var res = try JsonParseResult(T).initByParsing(allocator, body);
// //             return res.result();
// //         } else {
// //             return error.UnsupportedContentType;
// //         }
// //     }

// //     return error.FailedToParseNoBody;
// // }

// // how do I test it?
// // test parseBody {
// //     const req = zap.Request{
// //         .h =
// //     };
// // }

// // non-working experiement
// // pub fn parseBody(comptime T: type, allocator: Allocator, req: *const zap.Request) !SubType(T) {
// //     req.parseBody() catch {
// //         return error.FailedToParseBody;
// //     };

// //     // huh? how is this []const u8?
// //     if (req.body) |body| {
// //         const content_type = req.getHeader("content-type");

// //         if (content_type == null) {
// //             return error.UnsupportedContentType;
// //         }

// //         if (std.mem.startsWith(u8, content_type.?, "application/json")) {

// //             const parsed = std.json.parseFromSlice(T, allocator, body, .{}) catch {
// //                 return error.FailedToParseBody;
// //             };
// //             // parsed.deinit needs a pointer to itself (it cant be captured automatically)

// //             // i cant do this...
// //             const wrap = struct {
// //                 fn innerFn() void {
// //                     json.Parsed(T).deinit(parsed);
// //                 }
// //             };
// //             return .{
// //                 .value = parsed.value,
// //                 .deinit = wrap.innerFn,
// //             };

// //             // or this
// //             // return .{
// //             //     .value = parsed.value,
// //             //     .deinit = parsed.deinit,
// //             // };
// //         } else {
// //             return error.UnsupportedContentType;
// //         }
// //     }

// //     return error.FailedToParseNoBody;
// // }
