const std = @import("std");
pub const jq = @import("./jq.zig");
pub const jv = @import("./jv.zig");

pub fn run(allocator: std.mem.Allocator, input: []const u8, query: []const u8) ![]const u8 {
    const parsed = try jv.parse(allocator, input);
    defer parsed.deinit();
    const json = parsed.value;

    var runtime = try jq.Runtime.init(allocator);
    defer runtime.deinit();
    try runtime.compileFromSlice(query);
    try runtime.start(json);
    const result = try runtime.next() orelse return error.NoResult;
    const output = try jv.stringify(allocator, result);
    return output;
}

fn testRun(expected: []const u8, input: []const u8, query: []const u8) !void {
    try testRunMultiple(&.{expected}, input, query);
}

fn testRunMultiple(expected: []const []const u8, input: []const u8, query: []const u8) !void {
    const allocator = std.testing.allocator;

    const parsed = try jv.parse(allocator, input);
    defer parsed.deinit();
    const json = parsed.value;

    var runtime = try jq.Runtime.init(allocator);
    defer runtime.deinit();
    try runtime.compileFromSlice(query);
    try runtime.start(json);

    for (expected) |ex| {
        const result_value = try runtime.next() orelse return error.NoResult;
        const result = try jv.stringify(allocator, result_value);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(ex, result);
    }

    try std.testing.expectEqual(null, try runtime.next());
}

test "literals" {
    try testRun("\"hello\"", "null", "\"hello\"");
    try testRun("\"\"", "null", "\"\"");
    try testRun("\"hello\\nworld\"", "null", "\"hello\\nworld\"");
    try testRun("\"hello\"", "{\"a\":1}", "\"hello\"");
    try testRun("[]", "null", "[]");
    try testRun("{}", "null", "{}");
    try testRun("[]", "{\"a\":1}", "[]");
    try testRun("{}", "[1,2,3]", "{}");
}

test "identity filter" {
    try testRun("null", "null", ".");
    try testRun("false", "false", ".");
    try testRun("true", "true", ".");
    try testRun("123", "123", ".");
    try testRun("3.1415", "3.1415", ".");
    try testRun("[]", "[]", ".");
    try testRun("{}", "{}", ".");
    try testRun(
        \\[
        \\  1,
        \\  2,
        \\  3
        \\]
    , "[1,2,3]", ".");
    try testRun(
        \\{
        \\  "a": 123
        \\}
    , "{\"a\":123}", ".");
}

test "index access" {
    try testRun("null", "[]", ".[0]");
    try testRun("1", "[1,2,3]", ".[0]");
    try testRun("null", "[1,2,3]", ".[5]");
    try testRun("11", "[0,1,2,3,4,5,6,7,8,9,10,11,12]", ".[11]");
    try testRun("100",
        \\[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,
        \\ 21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
        \\ 41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,
        \\ 61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,
        \\ 81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100]
    , ".[100]");

    try testRun("123", "{\"a\":123}", ".a");
    try testRun("null", "{\"a\":123}", ".b");
    try testRun("\"hello\"", "{\"foo\":\"hello\"}", ".foo");
    try testRun(
        \\[
        \\  1,
        \\  2,
        \\  3
        \\]
    , "{\"arr\":[1,2,3]}", ".arr");
    try testRun(
        \\{
        \\  "bar": true
        \\}
    , "{\"foo\":{\"bar\":true}}", ".foo");

    try testRun("123", "{\"a\":123}", ".[\"a\"]");
    try testRun("null", "{\"a\":123}", ".[\"b\"]");
    try testRun("\"hello\"", "{\"foo\":\"hello\"}", ".[\"foo\"]");

    try testRun("42", "{\"foo bar\":42}", ".[\"foo bar\"]");
    try testRun("\"value\"", "{\"key with spaces\":\"value\"}", ".[\"key with spaces\"]");

    try testRun("\"world\"", "{\"key\":\"hello\",\"hello\":\"world\"}", ".[.key]");
    try testRun("3", "[1,2,3,4,5]", ".[1 + 1]");
    try testRun("5", "[1,2,3,4,5]", ".[2 * 2]");
}

test "arithmetic operations" {
    try testRun("579", "null", "123 + 456");
    try testRun("35", "{\"a\":12,\"b\":23}", ".a + .b");
    try testRun("12", "[1,2,3]", ".[1] + 10");
    try testRun("6", "null", "1 + 2 + 3");

    try testRun("333", "null", "456 - 123");
    try testRun("-11", "{\"a\":12,\"b\":23}", ".a - .b");
    try testRun("-8", "[1,2,3]", ".[1] - 10");
    try testRun("-4", "null", "1 - 2 - 3");

    try testRun("56088", "null", "123 * 456");
    try testRun("276", "{\"a\":12,\"b\":23}", ".a * .b");
    try testRun("20", "[1,2,3]", ".[1] * 10");
    try testRun("6", "null", "1 * 2 * 3");

    try testRun("3", "null", "456 / 123");
    try testRun("0", "{\"a\":12,\"b\":23}", ".a / .b");
    try testRun("5", "[10,20,30]", ".[1] / 4");
    try testRun("2", "null", "12 / 2 / 3");

    try testRun("87", "null", "456 % 123");
    try testRun("12", "{\"a\":12,\"b\":23}", ".a % .b");
    try testRun("0", "[1,2,3]", ".[1] % 2");
    try testRun("0", "null", "12 % 2 % 3");
}

test "pipe operator" {
    try testRun("123", "{\"a\":{\"b\":123}}", ".a | .b");
    try testRun("584", "null", "123 + 456 | . + 5");
    try testRun("10", "null", "1 | . + 2 | . + 3 | . | 4 + .");
}

test "comma operator" {
    try testRunMultiple(&.{ "12", "34", "56" }, "{\"a\":12,\"b\":34,\"c\":56}", ".a,.b,.c");
}

test "optional index" {
    try testRun("1", "[1,2,3]", ".[0]?");
    try testRun("null", "[1,2,3]", ".[5]?");
    try testRun("null", "null", ".[0]?");
    try testRun("null", "123", ".[0]?");

    try testRun("123", "{\"a\":123}", ".a?");
    try testRun("null", "{\"a\":123}", ".b?");
    try testRun("null", "null", ".a?");
    try testRun("null", "[1,2,3]", ".a?");
}

test "comparison operators" {
    try testRun("true", "null", "1 == 1");
    try testRun("false", "null", "1 == 2");
    try testRun("false", "null", "1 != 1");
    try testRun("true", "null", "1 != 2");

    try testRun("true", "null", "1.5 == 1.5");
    try testRun("false", "null", "1.5 == 2.5");

    try testRun("true", "null", "1 == 1.0");
    try testRun("false", "null", "1 == 1.5");

    try testRun("true", "{\"a\":\"foo\",\"b\":\"foo\"}", ".a == .b");
    try testRun("false", "{\"a\":\"foo\",\"b\":\"bar\"}", ".a == .b");
    try testRun("true", "{\"a\":\"foo\",\"b\":\"bar\"}", ".a != .b");

    try testRun("true", "null", ". == null");
    try testRun("false", "null", ". != null");

    try testRun("true", "true", ". == true");
    try testRun("false", "true", ". == false");
    try testRun("true", "false", ". != true");

    try testRun("true", "null", "1 < 2");
    try testRun("false", "null", "2 < 1");
    try testRun("false", "null", "1 < 1");

    try testRun("true", "null", "2 > 1");
    try testRun("false", "null", "1 > 2");
    try testRun("false", "null", "1 > 1");

    try testRun("true", "null", "1 <= 2");
    try testRun("true", "null", "1 <= 1");
    try testRun("false", "null", "2 <= 1");

    try testRun("true", "null", "2 >= 1");
    try testRun("true", "null", "1 >= 1");
    try testRun("false", "null", "1 >= 2");

    try testRun("true", "null", "1.5 < 2.5");
    try testRun("false", "null", "2.5 < 1.5");

    try testRun("true", "null", "1 < 1.5");
    try testRun("false", "null", "2 < 1.5");

    try testRun("true", "{\"a\":\"abc\",\"b\":\"abd\"}", ".a < .b");
    try testRun("false", "{\"a\":\"abd\",\"b\":\"abc\"}", ".a < .b");
    try testRun("true", "{\"a\":\"abc\",\"b\":\"abc\"}", ".a <= .b");
    try testRun("true", "{\"a\":\"abd\",\"b\":\"abc\"}", ".a > .b");
    try testRun("true", "{\"a\":\"abc\",\"b\":\"abc\"}", ".a >= .b");
}
