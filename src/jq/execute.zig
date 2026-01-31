const std = @import("std");
const jv = @import("../jv.zig");
const tokenize = @import("./tokenize.zig").tokenize;
const parse = @import("./parse.zig").parse;
const Instr = @import("./codegen.zig").Instr;
const codegen = @import("./codegen.zig").codegen;

pub const ExecuteError = error{
    Unimplemented,
    InvalidType,
    InternalError,
} || jv.ops.OpsError;

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
        // Values beyond the savepoint boundary belong to a previous segment
        // that may be restored later. We must clone them because restore()
        // expects those values to be still available.
        if (self.stack.isBeyondSavepointBoundary()) {
            return self.stack.pop().clone();
        }
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
        const top = self.stack.top().*.clone();
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

    pub fn restore(self: *Self, allocator: std.mem.Allocator) void {
        self.discardAllValuesAboveSavepoint(allocator);
        self.stack.restore();
    }

    pub fn ensureSize(self: *Self, n: usize) bool {
        return self.stack.ensureSize(n);
    }

    // Discard all values pushed above the current savepoint.
    fn discardAllValuesAboveSavepoint(self: *Self, allocator: std.mem.Allocator) void {
        if (self.stack.savepoints.items.len == 0) return;
        const sp = self.stack.savepoints.items[self.stack.savepoints.items.len - 1];

        var seg_idx = self.stack.active_segment_index;
        while (seg_idx > sp.segment_index) : (seg_idx -= 1) {
            const seg = &self.stack.segments.items[seg_idx];
            for (seg.data.items) |item| {
                item.deinit(allocator);
            }
        }

        const seg = &self.stack.segments.items[sp.segment_index];
        if (seg.data.items.len > sp.offset) {
            for (seg.data.items[sp.offset..]) |item| {
                item.deinit(allocator);
            }
        }
    }
};

pub const Runtime = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    values: ValueStack,
    forks: std.ArrayList(usize),
    instrs: []const Instr,
    pc: usize,
    constants: std.ArrayList(jv.Value),
    variables: std.ArrayList(jv.Value),

    pub fn init(allocator: std.mem.Allocator) !Self {
        // The order of this table must match with ConstIndex's order.
        var constants = try std.ArrayList(jv.Value).initCapacity(allocator, 4);
        try constants.append(allocator, jv.Value.null);
        try constants.append(allocator, jv.Value.false);
        try constants.append(allocator, jv.Value.true);
        try constants.append(allocator, jv.Value.initArray(try jv.Array.init(allocator)));

        return .{
            .allocator = allocator,
            .values = try ValueStack.init(allocator),
            .forks = .{},
            .instrs = &[_]Instr{},
            .pc = 0,
            .constants = constants,
            .variables = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.variables.items) |value| {
            value.deinit(self.allocator);
        }
        self.variables.deinit(self.allocator);
        for (self.constants.items) |value| {
            switch (value) {
                .string => |s| self.allocator.free(s),
                else => value.deinit(self.allocator),
            }
        }
        self.constants.deinit(self.allocator);
        self.allocator.free(self.instrs);
        self.values.deinit();
        self.forks.deinit(self.allocator);
    }

    pub fn compileFromReader(self: *Self, reader: *std.Io.Reader) !void {
        std.debug.assert(self.instrs.len == 0);

        var compile_allocator = std.heap.ArenaAllocator.init(self.allocator);
        defer compile_allocator.deinit();
        const tokens = try tokenize(compile_allocator.allocator(), reader);
        const ast = try parse(self.allocator, compile_allocator.allocator(), tokens, &self.constants);
        const instrs = try codegen(self.allocator, ast);
        self.instrs = instrs;
        // std.debug.print("BEGIN\n", .{});
        // for (self.instrs) |instr| {
        //     std.debug.print("{}\n", .{instr});
        // }
        // std.debug.print("END\n", .{});
    }

    pub fn compileFromSlice(self: *Self, query: []const u8) !void {
        var reader = std.Io.Reader.fixed(query);
        return self.compileFromReader(&reader);
    }

    pub fn start(self: *Self, input: jv.Value) !void {
        try self.values.push(input.clone());
    }

    pub fn next(self: *Self) !?jv.Value {
        std.debug.assert(self.instrs.len > 0);

        _ = self.restore_stack();

        while (self.pc < self.instrs.len) : (self.pc += 1) {
            const cur = self.instrs[self.pc];
            // std.debug.print("{}\n", .{cur});
            switch (cur) {
                .nop => {},
                .ret => {
                    self.pc += 1;
                    return self.values.pop();
                },
                .jump => |offset| {
                    self.pc += offset - 1;
                },
                .jump_unless => |offset| {
                    std.debug.assert(self.values.ensureSize(1));

                    const value = self.values.pop();
                    if (jv.ops.isFalsy(value)) {
                        self.pc += offset - 1;
                    }
                    // FIXME: optimize pop and push
                    try self.values.push(value);
                },
                .fork => |offset| {
                    try self.save_stack(self.pc + offset);
                },
                .backtrack => {
                    if (self.restore_stack()) {
                        self.pc -= 1;
                    }
                },
                .dup => {
                    std.debug.assert(self.values.ensureSize(1));

                    try self.values.dup();
                },
                .pop => {
                    std.debug.assert(self.values.ensureSize(1));

                    self.values.pop().deinit(self.allocator);
                },
                .subexp_begin => try self.values.dup(),
                .subexp_end => try self.values.swap(),
                .index => {
                    std.debug.assert(self.values.ensureSize(2));

                    const base = self.values.pop();
                    const key = self.values.pop();
                    const result = (try jv.ops.index(base, key)).clone();
                    base.deinit(self.allocator);
                    key.deinit(self.allocator);
                    try self.values.push(result);
                },
                .index_opt => {
                    std.debug.assert(self.values.ensureSize(2));

                    const base = self.values.pop();
                    const key = self.values.pop();
                    const idx_result: jv.Value = jv.ops.index(base, key) catch .null;
                    const result = idx_result.clone();
                    base.deinit(self.allocator);
                    key.deinit(self.allocator);
                    try self.values.push(result);
                },
                .slice => {
                    std.debug.assert(self.values.ensureSize(3));

                    const base = self.values.pop();
                    const to = self.values.pop();
                    const from = self.values.pop();
                    const result = try jv.ops.slice(self.allocator, base, from, to);
                    base.deinit(self.allocator);
                    to.deinit(self.allocator);
                    from.deinit(self.allocator);
                    try self.values.push(result);
                },
                .slice_opt => {
                    std.debug.assert(self.values.ensureSize(3));

                    const base = self.values.pop();
                    const to = self.values.pop();
                    const from = self.values.pop();
                    const result = jv.ops.slice(self.allocator, base, from, to) catch jv.Value.null;
                    base.deinit(self.allocator);
                    to.deinit(self.allocator);
                    from.deinit(self.allocator);
                    try self.values.push(result);
                },
                .add => {
                    std.debug.assert(self.values.ensureSize(3));

                    self.values.pop().deinit(self.allocator);
                    const lhs = try self.values.popInteger();
                    const rhs = try self.values.popInteger();
                    const result = lhs + rhs;
                    try self.values.push(jv.Value.initInteger(result));
                },
                .sub => {
                    std.debug.assert(self.values.ensureSize(3));

                    self.values.pop().deinit(self.allocator);
                    const lhs = try self.values.popInteger();
                    const rhs = try self.values.popInteger();
                    const result = lhs - rhs;
                    try self.values.push(jv.Value.initInteger(result));
                },
                .mul => {
                    std.debug.assert(self.values.ensureSize(3));

                    self.values.pop().deinit(self.allocator);
                    const lhs = try self.values.popInteger();
                    const rhs = try self.values.popInteger();
                    const result = lhs * rhs;
                    try self.values.push(jv.Value.initInteger(result));
                },
                .div => {
                    std.debug.assert(self.values.ensureSize(3));

                    self.values.pop().deinit(self.allocator);
                    const lhs = try self.values.popInteger();
                    const rhs = try self.values.popInteger();
                    const result = @divTrunc(lhs, rhs);
                    try self.values.push(jv.Value.initInteger(result));
                },
                .mod => {
                    std.debug.assert(self.values.ensureSize(3));

                    self.values.pop().deinit(self.allocator);
                    const lhs = try self.values.popInteger();
                    const rhs = try self.values.popInteger();
                    const result = @mod(lhs, rhs);
                    try self.values.push(jv.Value.initInteger(result));
                },
                .eq => {
                    std.debug.assert(self.values.ensureSize(3));

                    self.values.pop().deinit(self.allocator);
                    const lhs = self.values.pop();
                    const rhs = self.values.pop();
                    const result = try jv.ops.compare(lhs, rhs, .eq);
                    try self.values.push(jv.Value.initBool(result));
                },
                .ne => {
                    std.debug.assert(self.values.ensureSize(3));

                    self.values.pop().deinit(self.allocator);
                    const lhs = self.values.pop();
                    const rhs = self.values.pop();
                    const result = try jv.ops.compare(lhs, rhs, .ne);
                    try self.values.push(jv.Value.initBool(result));
                },
                .lt => {
                    std.debug.assert(self.values.ensureSize(3));

                    self.values.pop().deinit(self.allocator);
                    const lhs = self.values.pop();
                    const rhs = self.values.pop();
                    const result = try jv.ops.compare(lhs, rhs, .lt);
                    try self.values.push(jv.Value.initBool(result));
                },
                .gt => {
                    std.debug.assert(self.values.ensureSize(3));

                    self.values.pop().deinit(self.allocator);
                    const lhs = self.values.pop();
                    const rhs = self.values.pop();
                    const result = try jv.ops.compare(lhs, rhs, .gt);
                    try self.values.push(jv.Value.initBool(result));
                },
                .le => {
                    std.debug.assert(self.values.ensureSize(3));

                    self.values.pop().deinit(self.allocator);
                    const lhs = self.values.pop();
                    const rhs = self.values.pop();
                    const result = try jv.ops.compare(lhs, rhs, .le);
                    try self.values.push(jv.Value.initBool(result));
                },
                .ge => {
                    std.debug.assert(self.values.ensureSize(3));

                    self.values.pop().deinit(self.allocator);
                    const lhs = self.values.pop();
                    const rhs = self.values.pop();
                    const result = try jv.ops.compare(lhs, rhs, .ge);
                    try self.values.push(jv.Value.initBool(result));
                },
                .alt => {
                    std.debug.assert(self.values.ensureSize(3));

                    self.values.pop().deinit(self.allocator);
                    const lhs = self.values.pop();
                    const rhs = self.values.pop();
                    if (jv.ops.isFalsy(lhs)) {
                        lhs.deinit(self.allocator);
                        try self.values.push(rhs);
                    } else {
                        rhs.deinit(self.allocator);
                        try self.values.push(lhs);
                    }
                },
                .@"const" => |idx| {
                    std.debug.assert(self.values.ensureSize(1));

                    self.values.pop().deinit(self.allocator);
                    try self.values.push(self.constants.items[@intFromEnum(idx)].clone());
                },
                .load => |idx| {
                    try self.values.push(self.variables.items[@intFromEnum(idx)].clone());
                },
                .store => |idx| {
                    std.debug.assert(self.values.ensureSize(1));

                    // TODO: Allocate all local variables at startup.
                    while (self.variables.items.len <= @intFromEnum(idx)) {
                        try self.variables.append(self.allocator, jv.Value.null);
                    }
                    self.variables.items[@intFromEnum(idx)].deinit(self.allocator);
                    self.variables.items[@intFromEnum(idx)] = self.values.pop();
                },
                .append => |idx| {
                    std.debug.assert(self.values.ensureSize(1));

                    const var_ptr = &self.variables.items[@intFromEnum(idx)];
                    try var_ptr.arrayAppend(self.allocator, self.values.pop());
                },
            }
        }

        return null;
    }

    fn save_stack(self: *Self, target_pc: usize) !void {
        try self.forks.append(self.allocator, target_pc);
        try self.values.save();
    }

    fn restore_stack(self: *Self) bool {
        if (self.forks.pop()) |target_pc| {
            self.pc = target_pc;
            self.values.restore(self.allocator);
            return true;
        }
        return false;
    }
};
