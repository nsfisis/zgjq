const std = @import("std");
const Value = @import("./value.zig").Value;

pub const Parsed = struct {
    value: Value,
    arena: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *const Parsed) void {
        const arena = self.arena;
        const allocator = self.allocator;
        arena.deinit();
        allocator.destroy(arena);
    }
};

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Parsed {
    const internal = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    return .{
        .value = .{ ._internal = internal.value },
        .arena = internal.arena,
        .allocator = allocator,
    };
}
