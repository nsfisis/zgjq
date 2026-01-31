const std = @import("std");

const SEGMENT_INITIAL_CAPACITY: usize = 16;

const StackPosition = struct {
    segment_index: usize,
    offset: usize,
};

fn Segment(comptime T: type) type {
    return struct {
        const Self = @This();

        data: std.ArrayList(T),
        previous_position: StackPosition,

        fn init(allocator: std.mem.Allocator, previous_position: StackPosition) !Self {
            const data = try std.ArrayList(T).initCapacity(allocator, SEGMENT_INITIAL_CAPACITY);
            return .{
                .data = data,
                .previous_position = previous_position,
            };
        }

        fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.data.deinit(allocator);
        }

        fn len(self: *const Self) usize {
            return self.data.items.len;
        }

        fn top(self: *Self) *T {
            return &self.data.items[self.data.items.len - 1];
        }

        fn itemAt(self: *Self, index: usize) *T {
            return &self.data.items[index];
        }

        fn pop(self: *Self) T {
            return self.data.pop().?;
        }

        fn push(self: *Self, allocator: std.mem.Allocator, value: T) !void {
            try self.data.append(allocator, value);
        }

        fn clear(self: *Self) void {
            self.data.clearRetainingCapacity();
        }

        fn shrink(self: *Self, new_len: usize) void {
            self.data.shrinkRetainingCapacity(new_len);
        }
    };
}

pub fn SaveableStack(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        segments: std.ArrayList(Segment(T)),
        active_segment_index: usize,
        savepoints: std.ArrayList(StackPosition),

        pub fn init(allocator: std.mem.Allocator) !Self {
            var stack = Self{
                .segments = .{},
                .active_segment_index = 0,
                .savepoints = .{},
                .allocator = allocator,
            };

            const first_segment = try Segment(T).init(allocator, .{ .segment_index = 0, .offset = 0 });
            try stack.segments.append(allocator, first_segment);

            return stack;
        }

        pub fn deinit(self: *Self) void {
            for (self.segments.items) |*seg| {
                seg.deinit(self.allocator);
            }
            self.segments.deinit(self.allocator);
            self.savepoints.deinit(self.allocator);
        }

        pub fn push(self: *Self, value: T) !void {
            try self.activeSegment().push(self.allocator, value);
        }

        pub fn isEmpty(self: *Self) bool {
            const seg = self.activeSegment();

            if (seg.len() > 0) {
                return false;
            }

            return seg.previous_position.offset == 0;
        }

        pub fn isBeyondSavepointBoundary(self: *Self) bool {
            return self.activeSegment().len() == 0;
        }

        pub fn pop(self: *Self) T {
            std.debug.assert(!self.isEmpty());

            const seg = self.activeSegment();

            if (seg.len() > 0) {
                return seg.pop();
            }

            seg.previous_position.offset -= 1;
            const result = self.segmentAt(seg.previous_position.segment_index).itemAt(seg.previous_position.offset).*;

            if (seg.previous_position.offset == 0 and seg.previous_position.segment_index > 0) {
                seg.previous_position = self.segmentAt(seg.previous_position.segment_index).previous_position;
            }

            return result;
        }

        pub fn top(self: *Self) *T {
            std.debug.assert(!self.isEmpty());

            const seg = self.activeSegment();

            if (seg.len() > 0) {
                return seg.top();
            }

            const pos = seg.previous_position;
            return self.segmentAt(pos.segment_index).itemAt(pos.offset - 1);
        }

        pub fn ensureSize(self: *Self, n: usize) bool {
            return self.size() >= n;
        }

        pub fn size(self: *Self) usize {
            var total: usize = 0;
            var pos = StackPosition{
                .segment_index = self.active_segment_index,
                .offset = self.activeSegment().len(),
            };

            while (true) {
                total += pos.offset;
                if (pos.segment_index == 0) break;
                pos = self.segmentAt(pos.segment_index).previous_position;
            }

            return total;
        }

        pub fn save(self: *Self) !void {
            const current_pos = StackPosition{
                .segment_index = self.active_segment_index,
                .offset = self.activeSegment().len(),
            };

            try self.savepoints.append(self.allocator, current_pos);

            const effective_pos = self.activeSegment().previous_position;

            const new_seg_idx = self.active_segment_index + 1;

            if (new_seg_idx < self.segments.items.len) {
                const seg = &self.segments.items[new_seg_idx];
                seg.clear();
                seg.previous_position = if (current_pos.offset > 0) current_pos else effective_pos;
            } else {
                const pos = if (current_pos.offset > 0) current_pos else effective_pos;
                const new_segment = try Segment(T).init(self.allocator, pos);
                try self.segments.append(self.allocator, new_segment);
            }

            self.active_segment_index = new_seg_idx;
        }

        pub fn restore(self: *Self) void {
            std.debug.assert(self.savepoints.items.len > 0);

            const sp = self.savepoints.pop().?;

            while (self.active_segment_index > sp.segment_index) {
                self.activeSegment().clear();
                self.active_segment_index -= 1;
            }

            self.activeSegment().shrink(sp.offset);
        }

        fn activeSegment(self: *Self) *Segment(T) {
            std.debug.assert(self.segments.items.len > 0);

            return &self.segments.items[self.active_segment_index];
        }

        fn segmentAt(self: *Self, index: usize) *Segment(T) {
            return &self.segments.items[index];
        }
    };
}

test "basic push and pop" {
    var stack = try SaveableStack(i32).init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(10);
    try stack.push(20);
    try stack.push(30);

    try std.testing.expectEqual(30, stack.top().*);

    try std.testing.expectEqual(30, stack.pop());
    try std.testing.expectEqual(20, stack.pop());
    try std.testing.expectEqual(10, stack.pop());
}

test "save and restore" {
    var stack = try SaveableStack(i32).init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(1);
    try stack.push(2);

    try stack.save();

    try stack.push(3);
    try stack.push(4);

    try std.testing.expectEqual(4, stack.top().*);

    stack.restore();

    try std.testing.expectEqual(2, stack.top().*);
    try std.testing.expectEqual(2, stack.pop());
    try std.testing.expectEqual(1, stack.pop());
}

test "nested save and restore" {
    var stack = try SaveableStack(i32).init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(1);
    try stack.save();

    try stack.push(2);
    try stack.save();

    try stack.push(3);

    try std.testing.expectEqual(3, stack.top().*);

    stack.restore();
    try std.testing.expectEqual(2, stack.top().*);

    stack.restore();
    try std.testing.expectEqual(1, stack.top().*);
}

test "pop across segments" {
    var stack = try SaveableStack(i32).init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(1);
    try stack.push(2);

    try stack.save();

    try std.testing.expectEqual(2, stack.pop());
    try std.testing.expectEqual(1, stack.pop());
}

test "save restore with segment reuse" {
    var stack = try SaveableStack(i32).init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(100);
    try stack.save();
    try stack.push(200);
    stack.restore();

    try stack.save();
    try stack.push(300);

    try std.testing.expectEqual(300, stack.top().*);
    try std.testing.expectEqual(300, stack.pop());
    try std.testing.expectEqual(100, stack.pop());
}

test "save, pop from previous, push, restore" {
    var stack = try SaveableStack(i32).init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(1);
    try stack.push(2);

    try stack.save();

    try std.testing.expectEqual(2, stack.pop());
    try std.testing.expectEqual(1, stack.pop());

    try stack.push(3);

    try std.testing.expectEqual(3, stack.top().*);

    stack.restore();

    try std.testing.expectEqual(2, stack.top().*);
    try std.testing.expectEqual(2, stack.pop());
    try std.testing.expectEqual(1, stack.pop());
}

test "nested save with pop across multiple segments" {
    var stack = try SaveableStack(i32).init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(1);

    try stack.save();
    try stack.push(2);

    try stack.save();
    try stack.push(3);

    try std.testing.expectEqual(3, stack.pop());
    try std.testing.expectEqual(2, stack.pop());
    try std.testing.expectEqual(1, stack.pop());

    stack.restore();

    try std.testing.expectEqual(2, stack.top().*);
    try std.testing.expectEqual(2, stack.pop());
    try std.testing.expectEqual(1, stack.pop());
}

test "save on empty segment after pop" {
    var stack = try SaveableStack(i32).init(std.testing.allocator);
    defer stack.deinit();

    try stack.push(1);
    try stack.push(2);

    try stack.save();

    try std.testing.expectEqual(2, stack.pop());
    try std.testing.expectEqual(1, stack.pop());

    try stack.save();

    try stack.push(3);
    try std.testing.expectEqual(3, stack.top().*);

    stack.restore();

    try std.testing.expect(stack.isEmpty());

    stack.restore();

    try std.testing.expectEqual(2, stack.top().*);
    try std.testing.expectEqual(2, stack.pop());
    try std.testing.expectEqual(1, stack.pop());
}

test "isEmpty" {
    var stack = try SaveableStack(i32).init(std.testing.allocator);
    defer stack.deinit();

    try std.testing.expect(stack.isEmpty());

    try stack.push(1);
    try std.testing.expect(!stack.isEmpty());

    try stack.push(2);
    try std.testing.expect(!stack.isEmpty());

    _ = stack.pop();
    try std.testing.expect(!stack.isEmpty());

    _ = stack.pop();
    try std.testing.expect(stack.isEmpty());
}

test "isEmpty with save and restore" {
    var stack = try SaveableStack(i32).init(std.testing.allocator);
    defer stack.deinit();

    try std.testing.expect(stack.isEmpty());

    try stack.push(1);
    try stack.save();

    try std.testing.expect(!stack.isEmpty());

    _ = stack.pop();
    try std.testing.expect(stack.isEmpty());

    stack.restore();
    try std.testing.expect(!stack.isEmpty());
}
