const std = @import("std");
pub const jq = @import("./jq.zig");
pub const jv = @import("./jv.zig");

pub fn run(allocator: std.mem.Allocator, input: []const u8, query: []const u8) ![]const u8 {
    var compile_allocator = std.heap.ArenaAllocator.init(allocator);
    defer compile_allocator.deinit();
    var reader = std.Io.Reader.fixed(query);
    const tokens = try jq.tokenize(compile_allocator.allocator(), &reader);
    const ast = try jq.parse(compile_allocator.allocator(), tokens);
    const instrs = try jq.compile(allocator, compile_allocator.allocator(), ast);
    defer allocator.free(instrs);

    const parsed = try jv.parse(allocator, input);
    defer parsed.deinit();
    const json = parsed.value;

    var runtime = try jq.Runtime.init(allocator, instrs, json);
    defer runtime.deinit();
    const result = try runtime.next() orelse return error.NoResult;
    const output = try jv.stringify(allocator, result);
    return output;
}

fn testRun(expected: []const u8, allocator: std.mem.Allocator, input: []const u8, query: []const u8) !void {
    var compile_allocator = std.heap.ArenaAllocator.init(allocator);
    defer compile_allocator.deinit();
    var reader = std.Io.Reader.fixed(query);
    const tokens = try jq.tokenize(compile_allocator.allocator(), &reader);
    const ast = try jq.parse(compile_allocator.allocator(), tokens);
    const instrs = try jq.compile(allocator, compile_allocator.allocator(), ast);
    defer allocator.free(instrs);

    const parsed = try jv.parse(allocator, input);
    defer parsed.deinit();
    const json = parsed.value;

    var runtime = try jq.Runtime.init(allocator, instrs, json);
    defer runtime.deinit();

    const result_value = try runtime.next() orelse return error.NoResult;
    const result = try jv.stringify(allocator, result_value);
    defer allocator.free(result);
    try std.testing.expectEqualStrings(expected, result);

    try std.testing.expectEqual(null, try runtime.next());
}

test "identity filter" {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const allocator = debug_allocator.allocator();

    try testRun("null", allocator, "null", ".");
    try testRun("false", allocator, "false", ".");
    try testRun("true", allocator, "true", ".");
    try testRun("123", allocator, "123", ".");
    try testRun("3.1415", allocator, "3.1415", ".");
    try testRun("[]", allocator, "[]", ".");
    try testRun("{}", allocator, "{}", ".");
    try testRun("[1,2,3]", allocator, "[1,2,3]", ".");
    try testRun("{\"a\":123}", allocator, "{\"a\":123}", ".");
}

test "array index filter" {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const allocator = debug_allocator.allocator();

    try testRun("null", allocator, "[]", ".[0]");
    try testRun("1", allocator, "[1,2,3]", ".[0]");
    try testRun("null", allocator, "[1,2,3]", ".[5]");
    try testRun("11", allocator, "[0,1,2,3,4,5,6,7,8,9,10,11,12]", ".[11]");
    try testRun("100", allocator,
        \\[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,
        \\ 21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
        \\ 41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,
        \\ 61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,
        \\ 81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100]
    , ".[100]");
}

test "object key filter" {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const allocator = debug_allocator.allocator();

    try testRun("123", allocator, "{\"a\":123}", ".a");
    try testRun("null", allocator, "{\"a\":123}", ".b");
    try testRun("\"hello\"", allocator, "{\"foo\":\"hello\"}", ".foo");
    try testRun("[1,2,3]", allocator, "{\"arr\":[1,2,3]}", ".arr");
    try testRun("{\"bar\":true}", allocator, "{\"foo\":{\"bar\":true}}", ".foo");
}

test "addition" {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const allocator = debug_allocator.allocator();

    try testRun("579", allocator, "null", "123 + 456");
    try testRun("35", allocator, "{\"a\":12,\"b\":23}", ".a + .b");
    try testRun("12", allocator, "[1,2,3]", ".[1] + 10");
    try testRun("6", allocator, "null", "1 + 2 + 3");
}

test "pipe operator" {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const allocator = debug_allocator.allocator();

    try testRun("123", allocator, "{\"a\":{\"b\":123}}", ".a | .b");
    try testRun("584", allocator, "null", "123 + 456 | . + 5");
    try testRun("10", allocator, "null", "1 | . + 2 | . + 3 | . | 4 + .");
}
