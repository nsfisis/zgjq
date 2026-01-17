const std = @import("std");
const jv = @import("../jv.zig");
const Instr = @import("./compile.zig").Instr;

pub const ExecuteError = error{
    Unimplemented,
    InvalidType,
    InternalError,
};

const ValueStack = struct {
    const Self = @This();
    const Stack = std.ArrayList(jv.Value);

    stack: Stack,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .stack = try Stack.initCapacity(allocator, 16),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit(self.allocator);
    }

    pub fn push(self: *Self, value: jv.Value) !void {
        try self.stack.append(self.allocator, value);
    }

    pub fn pop(self: *Self) ExecuteError!jv.Value {
        return self.stack.pop() orelse return error.InternalError;
    }

    pub fn popInteger(self: *Self) ExecuteError!i64 {
        const value = try self.pop();
        return switch (value) {
            .integer => |i| i,
            else => error.InvalidType,
        };
    }

    pub fn popNumber(self: *Self) ExecuteError!f64 {
        const value = try self.pop();
        return switch (value) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            else => error.InvalidType,
        };
    }

    pub fn popString(self: *Self) ExecuteError![]const u8 {
        const value = try self.pop();
        return switch (value) {
            .string => |s| s,
            else => error.InvalidType,
        };
    }

    pub fn popArray(self: *Self) ExecuteError!jv.Array {
        const value = try self.pop();
        return switch (value) {
            .array => |a| a,
            else => error.InvalidType,
        };
    }

    pub fn popObject(self: *Self) ExecuteError!jv.Object {
        const value = try self.pop();
        return switch (value) {
            .object => |o| o,
            else => error.InvalidType,
        };
    }
};

pub fn execute(allocator: std.mem.Allocator, instrs: []const Instr, input: jv.Value) !jv.Value {
    var value_stack = try ValueStack.init(allocator);
    defer value_stack.deinit();

    try value_stack.push(input);

    const len = instrs.len;
    var pc: usize = 0;
    while (pc < len) {
        const cur = instrs[pc];
        switch (cur) {
            .nop => {},
            .array_index => {
                const index: usize = @intCast(try value_stack.popInteger());
                const array = try value_stack.popArray();
                const result = if (index < array.items.len) array.items[index] else .null;
                try value_stack.push(result);
            },
            .object_key => |key| {
                const obj = try value_stack.popObject();
                const result = obj.get(key) orelse .null;
                try value_stack.push(result);
            },
            .literal => |value| {
                try value_stack.push(value.*);
            },
        }
        pc += 1;
    }

    return value_stack.pop();
}
