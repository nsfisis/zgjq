const std = @import("std");
const Value = @import("./value.zig").Value;

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !std.json.Parsed(Value) {
    return try std.json.parseFromSlice(Value, allocator, input, .{});
}
