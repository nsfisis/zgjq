const std = @import("std");
pub const jq = @import("./jq.zig");
pub const jv = @import("./jv.zig");

pub fn run(allocator: std.mem.Allocator, input: []const u8, query: []const u8) ![]const u8 {
    var compile_allocator = std.heap.ArenaAllocator.init(allocator);
    defer compile_allocator.deinit();
    const tokens = try jq.tokenize(compile_allocator.allocator(), query);
    const ast = try jq.parse(compile_allocator.allocator(), tokens);
    const instrs = try jq.compile(allocator, compile_allocator.allocator(), ast);
    defer allocator.free(instrs);

    const parsed = try jv.parse(allocator, input);
    defer parsed.deinit();
    const json = parsed.value;
    const result = try jq.execute(allocator, instrs, json);
    const output = try jv.stringify(allocator, result);
    return output;
}

fn testRun(expected: []const u8, allocator: std.mem.Allocator, input: []const u8, query: []const u8) !void {
    const result = try run(allocator, input, query);
    defer allocator.free(result);
    try std.testing.expectEqualStrings(expected, result);
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
}
