const std = @import("std");
const Value = @import("./value.zig").Value;
const Array = @import("./value.zig").Array;
const Object = @import("./value.zig").Object;

pub const OpsError = error{
    InvalidType,
    Unimplemented,
};

pub fn index(base: Value, key: Value) OpsError!Value {
    return switch (base) {
        .array => |a| switch (key) {
            .integer => |i| a.get(@intCast(i)),
            else => error.InvalidType,
        },
        .object => |o| switch (key) {
            .string => |s| o.get(s) orelse Value.null,
            else => error.InvalidType,
        },
        .null => Value.null,
        else => error.InvalidType,
    };
}

pub const CompareOp = enum { eq, ne, lt, gt, le, ge };

pub fn compare(lhs: Value, rhs: Value, op: CompareOp) OpsError!bool {
    const lhs_tag = lhs.kind();
    const rhs_tag = rhs.kind();

    if (lhs_tag != rhs_tag) {
        const lhs_is_number = lhs_tag == .integer or lhs_tag == .float;
        const rhs_is_number = rhs_tag == .integer or rhs_tag == .float;
        if (lhs_is_number and rhs_is_number) {
            return compareNumbers(lhs, rhs, op);
        }
        return error.InvalidType;
    }

    return switch (lhs) {
        .null => switch (op) {
            .eq => true,
            .ne => false,
            .lt, .gt, .le, .ge => error.Unimplemented,
        },
        .bool => |lhs_bool| {
            const rhs_bool = rhs.bool;
            return switch (op) {
                .eq => lhs_bool == rhs_bool,
                .ne => lhs_bool != rhs_bool,
                .lt, .gt, .le, .ge => error.Unimplemented,
            };
        },
        .integer, .float => compareNumbers(lhs, rhs, op),
        .string => |lhs_str| {
            const rhs_str = rhs.string;
            const order = std.mem.order(u8, lhs_str, rhs_str);
            return switch (op) {
                .eq => order == .eq,
                .ne => order != .eq,
                .lt => order == .lt,
                .gt => order == .gt,
                .le => order == .lt or order == .eq,
                .ge => order == .gt or order == .eq,
            };
        },
        .array => switch (op) {
            .eq, .ne => error.Unimplemented,
            .lt, .gt, .le, .ge => error.Unimplemented,
        },
        .object => switch (op) {
            .eq, .ne => error.Unimplemented,
            .lt, .gt, .le, .ge => error.Unimplemented,
        },
    };
}

fn compareNumbers(lhs: Value, rhs: Value, op: CompareOp) bool {
    const lhs_f: f64 = switch (lhs) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => unreachable,
    };
    const rhs_f: f64 = switch (rhs) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => unreachable,
    };
    return switch (op) {
        .eq => lhs_f == rhs_f,
        .ne => lhs_f != rhs_f,
        .lt => lhs_f < rhs_f,
        .gt => lhs_f > rhs_f,
        .le => lhs_f <= rhs_f,
        .ge => lhs_f >= rhs_f,
    };
}

test "index array" {
    var arr = try Array.init(std.testing.allocator);
    defer arr.deinit(std.testing.allocator);
    try arr.append(std.testing.allocator, Value.initInteger(10));
    try arr.append(std.testing.allocator, Value.initInteger(20));
    try arr.append(std.testing.allocator, Value.initInteger(30));

    const base = Value.initArray(arr);

    try std.testing.expectEqual(Value.initInteger(10), try index(base, Value.initInteger(0)));
    try std.testing.expectEqual(Value.initInteger(20), try index(base, Value.initInteger(1)));
    try std.testing.expectEqual(Value.initInteger(30), try index(base, Value.initInteger(2)));
    try std.testing.expectEqual(Value.null, try index(base, Value.initInteger(3)));
}

test "index object" {
    var obj = try Object.init(std.testing.allocator);
    defer obj.deinit(std.testing.allocator);
    try obj.set(std.testing.allocator, "foo", Value.initInteger(1));
    try obj.set(std.testing.allocator, "bar", Value.initInteger(2));

    const base = Value.initObject(obj);

    try std.testing.expectEqual(Value.initInteger(1), try index(base, Value.initString("foo")));
    try std.testing.expectEqual(Value.initInteger(2), try index(base, Value.initString("bar")));
    try std.testing.expectEqual(Value.null, try index(base, Value.initString("baz")));
}

test "index null" {
    try std.testing.expectEqual(Value.null, try index(Value.null, Value.initInteger(0)));
    try std.testing.expectEqual(Value.null, try index(Value.null, Value.initString("foo")));
}

test "index invalid type" {
    try std.testing.expectError(error.InvalidType, index(Value.initInteger(42), Value.initInteger(0)));
    try std.testing.expectError(error.InvalidType, index(Value.initString("foo"), Value.initInteger(0)));
}

test "compare integers" {
    try std.testing.expect(try compare(Value.initInteger(1), Value.initInteger(1), .eq));
    try std.testing.expect(!try compare(Value.initInteger(1), Value.initInteger(2), .eq));
    try std.testing.expect(try compare(Value.initInteger(1), Value.initInteger(2), .ne));
    try std.testing.expect(try compare(Value.initInteger(1), Value.initInteger(2), .lt));
    try std.testing.expect(try compare(Value.initInteger(2), Value.initInteger(1), .gt));
    try std.testing.expect(try compare(Value.initInteger(1), Value.initInteger(1), .le));
    try std.testing.expect(try compare(Value.initInteger(1), Value.initInteger(1), .ge));
}

test "compare floats" {
    try std.testing.expect(try compare(Value.initFloat(1.5), Value.initFloat(1.5), .eq));
    try std.testing.expect(try compare(Value.initFloat(1.5), Value.initFloat(2.5), .lt));
    try std.testing.expect(try compare(Value.initFloat(2.5), Value.initFloat(1.5), .gt));
}

test "compare mixed numbers" {
    try std.testing.expect(try compare(Value.initInteger(2), Value.initFloat(2.0), .eq));
    try std.testing.expect(try compare(Value.initFloat(1.5), Value.initInteger(2), .lt));
    try std.testing.expect(try compare(Value.initInteger(3), Value.initFloat(2.5), .gt));
}

test "compare strings" {
    try std.testing.expect(try compare(Value.initString("abc"), Value.initString("abc"), .eq));
    try std.testing.expect(try compare(Value.initString("abc"), Value.initString("abd"), .ne));
    try std.testing.expect(try compare(Value.initString("abc"), Value.initString("abd"), .lt));
    try std.testing.expect(try compare(Value.initString("abd"), Value.initString("abc"), .gt));
}

test "compare booleans" {
    try std.testing.expect(try compare(Value.initBool(true), Value.initBool(true), .eq));
    try std.testing.expect(try compare(Value.initBool(false), Value.initBool(false), .eq));
    try std.testing.expect(try compare(Value.initBool(true), Value.initBool(false), .ne));
}

test "compare null" {
    try std.testing.expect(try compare(Value.null, Value.null, .eq));
    try std.testing.expect(!try compare(Value.null, Value.null, .ne));
}

test "compare different types" {
    try std.testing.expectError(error.InvalidType, compare(Value.initInteger(1), Value.initString("1"), .eq));
    try std.testing.expectError(error.InvalidType, compare(Value.null, Value.initInteger(0), .eq));
}

pub fn isFalsy(value: Value) bool {
    return switch (value) {
        .null => true,
        .bool => |b| !b,
        else => false,
    };
}

pub fn isTruthy(value: Value) bool {
    return !isFalsy(value);
}

test "isFalsy" {
    try std.testing.expect(isFalsy(Value.null));
    try std.testing.expect(isFalsy(Value.initBool(false)));
    try std.testing.expect(!isFalsy(Value.initBool(true)));
    try std.testing.expect(!isFalsy(Value.initInteger(0)));
    try std.testing.expect(!isFalsy(Value.initInteger(1)));
    try std.testing.expect(!isFalsy(Value.initString("")));
    try std.testing.expect(!isFalsy(Value.initString("hello")));
}

test "isTruthy" {
    try std.testing.expect(!isTruthy(Value.null));
    try std.testing.expect(!isTruthy(Value.initBool(false)));
    try std.testing.expect(isTruthy(Value.initBool(true)));
    try std.testing.expect(isTruthy(Value.initInteger(0)));
    try std.testing.expect(isTruthy(Value.initInteger(1)));
    try std.testing.expect(isTruthy(Value.initString("")));
    try std.testing.expect(isTruthy(Value.initString("hello")));
}
