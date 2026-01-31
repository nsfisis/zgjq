const std = @import("std");

pub fn Rc(comptime T: type) type {
    const Cell = struct {
        value: T,
        ref_count: usize,
    };

    return struct {
        const Self = @This();

        cell: *Cell,

        pub fn init(allocator: std.mem.Allocator, value: T) std.mem.Allocator.Error!Self {
            const cell = try allocator.create(Cell);
            cell.* = .{ .value = value, .ref_count = 1 };
            return .{ .cell = cell };
        }

        pub fn release(self: Self, allocator: std.mem.Allocator) void {
            self.cell.ref_count -= 1;
            if (self.cell.ref_count == 0) {
                allocator.destroy(self.cell);
            }
        }

        pub fn retain(self: Self) Self {
            self.cell.ref_count += 1;
            return .{ .cell = self.cell };
        }

        pub fn isUnique(self: Self) bool {
            return self.cell.ref_count == 1;
        }

        pub fn get(self: Self) *T {
            return &self.cell.value;
        }
    };
}
