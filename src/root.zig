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
    defer result.deinit(allocator);
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
        defer result_value.deinit(allocator);
        const result = try jv.stringify(allocator, result_value);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(ex, result);
    }

    try std.testing.expectEqual(null, try runtime.next());
}

fn testDisasm(expected: []const u8, query: []const u8) !void {
    const allocator = std.testing.allocator;

    var runtime = try jq.Runtime.init(allocator);
    defer runtime.deinit();
    try runtime.compileFromSlice(query);

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try runtime.dumpDisasm(&writer);
    try writer.flush();

    try std.testing.expectEqualStrings(expected, buf[0..writer.end]);
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

test "slice" {
    // [begin:end]
    try testRun("[]", "[1,2,3]", ".[1:1]");
    try testRun(
        \\[
        \\  2,
        \\  3
        \\]
    , "[1,2,3]", ".[1:3]");
    try testRun(
        \\[
        \\  2
        \\]
    , "[1,2,3]", ".[1:2]");

    // [begin:]
    try testRun(
        \\[
        \\  2,
        \\  3
        \\]
    , "[1,2,3]", ".[1:]");
    try testRun(
        \\[
        \\  1,
        \\  2,
        \\  3
        \\]
    , "[1,2,3]", ".[0:]");

    // [:end]
    try testRun(
        \\[
        \\  1
        \\]
    , "[1,2,3]", ".[:1]");
    try testRun(
        \\[
        \\  1,
        \\  2
        \\]
    , "[1,2,3]", ".[:2]");

    try testRun(
        \\[
        \\  1,
        \\  2,
        \\  3
        \\]
    , "[1,2,3]", ".[0:10]");
    try testRun("[]", "[1,2,3]", ".[5:10]");

    try testRun(
        \\[
        \\  2,
        \\  3
        \\]
    , "[[1,2,3],[4,5,6]]", ".[0] | .[1:]");
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

test "and operator" {
    try testRun("true", "null", "true and true");
    try testRun("false", "null", "true and false");
    try testRun("false", "null", "false and true");
    try testRun("false", "null", "false and false");

    try testRun("false", "null", "null and true");
    try testRun("false", "null", "true and null");

    try testRun("true", "null", "1 and 1");
    try testRun("false", "null", "1 and false");
    try testRun("true", "null", "\"hello\" and true");

    try testRun("true", "{\"a\":true,\"b\":true}", ".a and .b");
    try testRun("false", "{\"a\":true,\"b\":false}", ".a and .b");
    try testRun("false", "{\"a\":false,\"b\":true}", ".a and .b");
}

test "or operator" {
    try testRun("true", "null", "true or true");
    try testRun("true", "null", "true or false");
    try testRun("true", "null", "false or true");
    try testRun("false", "null", "false or false");

    try testRun("true", "null", "null or true");
    try testRun("true", "null", "true or null");
    try testRun("false", "null", "null or false");
    try testRun("false", "null", "false or null");

    try testRun("true", "null", "1 or false");
    try testRun("true", "null", "false or 1");
    try testRun("false", "null", "false or false");

    try testRun("true", "{\"a\":true,\"b\":false}", ".a or .b");
    try testRun("true", "{\"a\":false,\"b\":true}", ".a or .b");
    try testRun("false", "{\"a\":false,\"b\":false}", ".a or .b");
}

test "alternative operator" {
    try testRun("\"default\"", "null", ". // \"default\"");
    try testRun("\"hello\"", "\"hello\"", ". // \"default\"");

    try testRun("\"default\"", "false", ". // \"default\"");
    try testRun("true", "true", ". // \"default\"");

    try testRun("123", "{\"a\":123}", ".a // \"default\"");
    try testRun("\"default\"", "{\"a\":123}", ".b // \"default\"");
    try testRun("\"default\"", "{\"a\":null}", ".a // \"default\"");

    try testRun("\"third\"", "null", "null // false // \"third\"");
    try testRun("\"first\"", "null", "\"first\" // \"second\" // \"third\"");

    try testRun("0", "0", ". // 42");
    try testRun("\"\"", "\"\"", ". // \"default\"");

    try testRun("[]", "[]", ". // \"default\"");
    try testRun("{}", "{}", ". // \"default\"");
}

test "array constructor" {
    try testRun(
        \\[
        \\  1,
        \\  2,
        \\  3
        \\]
    , "null", "[1,2,3]");
    try testRun(
        \\[
        \\  1,
        \\  2
        \\]
    , "{\"a\":1,\"b\":2}", "[.a, .b]");
    try testRun(
        \\[
        \\  3
        \\]
    , "null", "[1 + 2]");
    try testRun(
        \\[
        \\  1,
        \\  2,
        \\  3
        \\]
    , "[1,2,3]", "[.[0], .[1], .[2]]");
    try testRun(
        \\[
        \\  [
        \\    1,
        \\    2,
        \\    3
        \\  ]
        \\]
    , "[1,2,3]", "[.]");
    try testRun(
        \\[
        \\  true,
        \\  false
        \\]
    , "null", "[true, false]");
    try testRun(
        \\[
        \\  1,
        \\  [
        \\    1,
        \\    [
        \\      1,
        \\      2
        \\    ]
        \\  ]
        \\]
    , "{\"a\":1,\"b\":2}", "[.a, [.a, [.a, .b]]]");
}

test "each" {
    try testRunMultiple(&.{ "1", "2", "3" }, "[1,2,3]", ".[]");
    try testRunMultiple(&.{ "1", "2", "3" }, "[[1],[2],[3]]", ".[] | .[]");
}

test "disasm identity" {
    try testDisasm(
        \\0000 NOP
        \\0001 RET
        \\
    , ".");
}

test "disasm field access" {
    try testDisasm(
        \\0000 NOP
        \\0001 SUBEXP_BEGIN
        \\0002 CONST "foo"
        \\0003 SUBEXP_END
        \\0004 INDEX
        \\0005 RET
        \\
    , ".foo");
}

test "disasm pipe and comma" {
    try testDisasm(
        \\0000 NOP
        \\0001 SUBEXP_BEGIN
        \\0002 CONST "foo"
        \\0003 SUBEXP_END
        \\0004 INDEX
        \\0005 FORK 0012
        \\0006 NOP
        \\0007 SUBEXP_BEGIN
        \\0008 CONST "bar"
        \\0009 SUBEXP_END
        \\0010 INDEX
        \\0011 JUMP 0017
        \\0012 NOP
        \\0013 SUBEXP_BEGIN
        \\0014 CONST "baz"
        \\0015 SUBEXP_END
        \\0016 INDEX
        \\0017 RET
        \\
    , ".foo | .bar, .baz");
}

test "disasm array construction" {
    try testDisasm(
        \\0000 DUP
        \\0001 CONST []
        \\0002 STORE $0
        \\0003 NOP
        \\0004 EACH
        \\0005 APPEND $0
        \\0006 BACKTRACK
        \\0007 LOAD $0
        \\0008 RET
        \\
    , "[.[]]");
}

test "disasm arithmetic" {
    try testDisasm(
        \\0000 SUBEXP_BEGIN
        \\0001 CONST 1
        \\0002 SUBEXP_END
        \\0003 SUBEXP_BEGIN
        \\0004 NOP
        \\0005 SUBEXP_END
        \\0006 ADD
        \\0007 RET
        \\
    , ". + 1");
}

test "disasm optional index" {
    try testDisasm(
        \\0000 NOP
        \\0001 SUBEXP_BEGIN
        \\0002 CONST "foo"
        \\0003 SUBEXP_END
        \\0004 INDEX_OPT
        \\0005 RET
        \\
    , ".foo?");
}

test "disasm comparison" {
    try testDisasm(
        \\0000 SUBEXP_BEGIN
        \\0001 CONST 1
        \\0002 SUBEXP_END
        \\0003 SUBEXP_BEGIN
        \\0004 NOP
        \\0005 SUBEXP_END
        \\0006 EQ
        \\0007 RET
        \\
    , ". == 1");
}

test "disasm constants" {
    try testDisasm(
        \\0000 CONST null
        \\0001 RET
        \\
    , "null");
    try testDisasm(
        \\0000 CONST true
        \\0001 RET
        \\
    , "true");
    try testDisasm(
        \\0000 CONST false
        \\0001 RET
        \\
    , "false");
}

test "parentheses" {
    try testRun("123", "123", "(.)");
    try testRun("null", "null", "(.)");

    try testRun("9", "null", "(1 + 2) * 3");
    try testRun("7", "null", "1 + 2 * 3");
    try testRun("6", "null", "(1 + 2) | . * 2");
    try testRun("12", "null", "((1 + 2)) * (3 + 1)");
    try testRun("3", "{\"a\":1,\"b\":2}", "(.a + .b) | . + 0");
    try testRunMultiple(&.{ "1", "2" }, "null", "(1, 2)");

    try testRun(
        \\[
        \\  2,
        \\  4
        \\]
    , "null", "[(1, 2) * 2]");
}
