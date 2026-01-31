const std = @import("std");
const Value = @import("./value.zig").Value;
const Array = @import("./value.zig").Array;
const Object = @import("./value.zig").Object;

pub const Parsed = struct {
    value: Value,
    arena: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *const Parsed) void {
        self.value.deinit(self.allocator);
        const arena = self.arena;
        const allocator = self.allocator;
        arena.deinit();
        allocator.destroy(arena);
    }
};

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Parsed {
    const internal = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    const value = try convertValue(allocator, internal.value);
    return .{
        .value = value,
        .arena = internal.arena,
        .allocator = allocator,
    };
}

fn convertValue(allocator: std.mem.Allocator, v: std.json.Value) !Value {
    return switch (v) {
        .null => Value.null,
        .bool => |b| Value.initBool(b),
        .integer => |i| Value.initInteger(i),
        .float => |f| Value.initFloat(f),
        .string => |s| Value.initString(s),
        .array => |a| blk: {
            var arr = try Array.init(allocator);
            for (a.items) |item| {
                try arr.append(allocator, try convertValue(allocator, item));
            }
            break :blk Value.initArray(arr);
        },
        .object => |o| blk: {
            var obj = try Object.init(allocator);
            var it = o.iterator();
            while (it.next()) |entry| {
                try obj.set(allocator, entry.key_ptr.*, try convertValue(allocator, entry.value_ptr.*));
            }
            break :blk Value.initObject(obj);
        },
        .number_string => unreachable,
    };
}
