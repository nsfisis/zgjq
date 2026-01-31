const std = @import("std");
const Value = @import("./value.zig").Value;

pub fn stringify(allocator: std.mem.Allocator, value: Value) ![]u8 {
    return try std.json.Stringify.valueAlloc(allocator, value._internal, .{ .whitespace = .indent_2 });
}
