const std = @import("std");
const jv = @import("../jv.zig");
const Instr = @import("./compile.zig").Instr;

pub const ExecuteError = error{
    Unimplemented,
    InvalidType,
    InternalError,
};

const SaveableStack = @import("./saveable_stack.zig").SaveableStack;

const ValueStack = struct {
    const Self = @This();
    const Stack = SaveableStack(jv.Value);

    stack: Stack,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .stack = try Stack.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
    }

    pub fn push(self: *Self, value: jv.Value) !void {
        try self.stack.push(value);
    }

    pub fn pop(self: *Self) jv.Value {
        return self.stack.pop();
    }

    pub fn popInteger(self: *Self) ExecuteError!i64 {
        const value = self.pop();
        return switch (value) {
            .integer => |i| i,
            else => error.InvalidType,
        };
    }

    pub fn popNumber(self: *Self) ExecuteError!f64 {
        const value = self.pop();
        return switch (value) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            else => error.InvalidType,
        };
    }

    pub fn popString(self: *Self) ExecuteError![]const u8 {
        const value = self.pop();
        return switch (value) {
            .string => |s| s,
            else => error.InvalidType,
        };
    }

    pub fn popArray(self: *Self) ExecuteError!jv.Array {
        const value = self.pop();
        return switch (value) {
            .array => |a| a,
            else => error.InvalidType,
        };
    }

    pub fn popObject(self: *Self) ExecuteError!jv.Object {
        const value = self.pop();
        return switch (value) {
            .object => |o| o,
            else => error.InvalidType,
        };
    }

    pub fn dup(self: *Self) !void {
        const top = self.stack.top().*;
        try self.push(top);
    }

    pub fn swap(self: *Self) !void {
        std.debug.assert(self.ensureSize(2));

        const a = self.pop();
        const b = self.pop();
        try self.push(a);
        try self.push(b);
    }

    pub fn save(self: *Self) !void {
        try self.stack.save();
    }

    pub fn restore(self: *Self) void {
        self.stack.restore();
    }

    pub fn ensureSize(self: *Self, n: usize) bool {
        return self.stack.ensureSize(n);
    }
};

pub const Runtime = struct {
    const Self = @This();

    values: ValueStack,
    instrs: []const Instr,
    input: jv.Value,
    pc: usize,

    pub fn init(allocator: std.mem.Allocator, instrs: []const Instr, input: jv.Value) !Self {
        var self = Self{
            .values = try ValueStack.init(allocator),
            .instrs = instrs,
            .input = input,
            .pc = 0,
        };
        try self.values.push(input);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.values.deinit();
    }

    pub fn next(self: *Self) !?jv.Value {
        while (self.pc < self.instrs.len) : (self.pc += 1) {
            const cur = self.instrs[self.pc];
            switch (cur) {
                .nop => {},
                .ret => {
                    self.pc += 1;
                    return self.values.pop();
                },
                .subexp_begin => try self.values.dup(),
                .subexp_end => try self.values.swap(),
                .array_index => {
                    std.debug.assert(self.values.ensureSize(2));

                    const array = try self.values.popArray();
                    const index: usize = @intCast(try self.values.popInteger());
                    const result = if (index < array.items.len) array.items[index] else .null;
                    try self.values.push(result);
                },
                .add => {
                    std.debug.assert(self.values.ensureSize(3));

                    _ = self.values.pop();
                    const lhs = try self.values.popInteger();
                    const rhs = try self.values.popInteger();
                    const result = lhs + rhs;
                    try self.values.push(.{ .integer = result });
                },
                .object_key => |key| {
                    std.debug.assert(self.values.ensureSize(1));

                    const obj = try self.values.popObject();
                    const result = obj.get(key) orelse .null;
                    try self.values.push(result);
                },
                .literal => |value| {
                    std.debug.assert(self.values.ensureSize(1));

                    _ = self.values.pop();
                    try self.values.push(value.*);
                },
            }
        }

        return null;
    }
};
