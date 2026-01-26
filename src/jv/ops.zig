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
        .array => |arr| blk: {
            const idx: usize = @intCast(switch (key) {
                .integer => |i| i,
                else => return error.InvalidType,
            });
            break :blk if (idx < arr.items.len) arr.items[idx] else .null;
        },
        .object => |obj| blk: {
            const k = switch (key) {
                .string => |s| s,
                else => return error.InvalidType,
            };
            break :blk obj.get(k) orelse .null;
        },
        .null => .null,
        else => error.InvalidType,
    };
}

pub const CompareOp = enum { eq, ne, lt, gt, le, ge };

pub fn compare(lhs: Value, rhs: Value, op: CompareOp) OpsError!bool {
    const lhs_tag = std.meta.activeTag(lhs);
    const rhs_tag = std.meta.activeTag(rhs);

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
        .number_string => error.Unimplemented,
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
    var arr = Array.init(std.testing.allocator);
    defer arr.deinit();
    try arr.append(.{ .integer = 10 });
    try arr.append(.{ .integer = 20 });
    try arr.append(.{ .integer = 30 });

    const base = Value{ .array = arr };

    try std.testing.expectEqual(Value{ .integer = 10 }, try index(base, .{ .integer = 0 }));
    try std.testing.expectEqual(Value{ .integer = 20 }, try index(base, .{ .integer = 1 }));
    try std.testing.expectEqual(Value{ .integer = 30 }, try index(base, .{ .integer = 2 }));
    try std.testing.expectEqual(Value.null, try index(base, .{ .integer = 3 }));
}

test "index object" {
    var obj = Object.init(std.testing.allocator);
    defer obj.deinit();
    try obj.put("foo", .{ .integer = 1 });
    try obj.put("bar", .{ .integer = 2 });

    const base = Value{ .object = obj };

    try std.testing.expectEqual(Value{ .integer = 1 }, try index(base, .{ .string = "foo" }));
    try std.testing.expectEqual(Value{ .integer = 2 }, try index(base, .{ .string = "bar" }));
    try std.testing.expectEqual(Value.null, try index(base, .{ .string = "baz" }));
}

test "index null" {
    try std.testing.expectEqual(Value.null, try index(.null, .{ .integer = 0 }));
    try std.testing.expectEqual(Value.null, try index(.null, .{ .string = "foo" }));
}

test "index invalid type" {
    try std.testing.expectError(error.InvalidType, index(.{ .integer = 42 }, .{ .integer = 0 }));
    try std.testing.expectError(error.InvalidType, index(.{ .string = "foo" }, .{ .integer = 0 }));
}

test "compare integers" {
    try std.testing.expect(try compare(.{ .integer = 1 }, .{ .integer = 1 }, .eq));
    try std.testing.expect(!try compare(.{ .integer = 1 }, .{ .integer = 2 }, .eq));
    try std.testing.expect(try compare(.{ .integer = 1 }, .{ .integer = 2 }, .ne));
    try std.testing.expect(try compare(.{ .integer = 1 }, .{ .integer = 2 }, .lt));
    try std.testing.expect(try compare(.{ .integer = 2 }, .{ .integer = 1 }, .gt));
    try std.testing.expect(try compare(.{ .integer = 1 }, .{ .integer = 1 }, .le));
    try std.testing.expect(try compare(.{ .integer = 1 }, .{ .integer = 1 }, .ge));
}

test "compare floats" {
    try std.testing.expect(try compare(.{ .float = 1.5 }, .{ .float = 1.5 }, .eq));
    try std.testing.expect(try compare(.{ .float = 1.5 }, .{ .float = 2.5 }, .lt));
    try std.testing.expect(try compare(.{ .float = 2.5 }, .{ .float = 1.5 }, .gt));
}

test "compare mixed numbers" {
    try std.testing.expect(try compare(.{ .integer = 2 }, .{ .float = 2.0 }, .eq));
    try std.testing.expect(try compare(.{ .float = 1.5 }, .{ .integer = 2 }, .lt));
    try std.testing.expect(try compare(.{ .integer = 3 }, .{ .float = 2.5 }, .gt));
}

test "compare strings" {
    try std.testing.expect(try compare(.{ .string = "abc" }, .{ .string = "abc" }, .eq));
    try std.testing.expect(try compare(.{ .string = "abc" }, .{ .string = "abd" }, .ne));
    try std.testing.expect(try compare(.{ .string = "abc" }, .{ .string = "abd" }, .lt));
    try std.testing.expect(try compare(.{ .string = "abd" }, .{ .string = "abc" }, .gt));
}

test "compare booleans" {
    try std.testing.expect(try compare(.{ .bool = true }, .{ .bool = true }, .eq));
    try std.testing.expect(try compare(.{ .bool = false }, .{ .bool = false }, .eq));
    try std.testing.expect(try compare(.{ .bool = true }, .{ .bool = false }, .ne));
}

test "compare null" {
    try std.testing.expect(try compare(.null, .null, .eq));
    try std.testing.expect(!try compare(.null, .null, .ne));
}

test "compare different types" {
    try std.testing.expectError(error.InvalidType, compare(.{ .integer = 1 }, .{ .string = "1" }, .eq));
    try std.testing.expectError(error.InvalidType, compare(.null, .{ .integer = 0 }, .eq));
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
    try std.testing.expect(isFalsy(.null));
    try std.testing.expect(isFalsy(.{ .bool = false }));
    try std.testing.expect(!isFalsy(.{ .bool = true }));
    try std.testing.expect(!isFalsy(.{ .integer = 0 }));
    try std.testing.expect(!isFalsy(.{ .integer = 1 }));
    try std.testing.expect(!isFalsy(.{ .string = "" }));
    try std.testing.expect(!isFalsy(.{ .string = "hello" }));
}

test "isTruthy" {
    try std.testing.expect(!isTruthy(.null));
    try std.testing.expect(!isTruthy(.{ .bool = false }));
    try std.testing.expect(isTruthy(.{ .bool = true }));
    try std.testing.expect(isTruthy(.{ .integer = 0 }));
    try std.testing.expect(isTruthy(.{ .integer = 1 }));
    try std.testing.expect(isTruthy(.{ .string = "" }));
    try std.testing.expect(isTruthy(.{ .string = "hello" }));
}
