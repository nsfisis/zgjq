const std = @import("std");
const jv = @import("../jv.zig");
const Ast = @import("./parse.zig").Ast;

pub const Opcode = enum {
    nop,
    subexp_begin,
    subexp_end,
    array_index,
    add,
    object_key,
    literal,
};

pub const Instr = union(Opcode) {
    nop,
    subexp_begin,
    subexp_end,
    array_index,
    add,
    object_key: []const u8,
    literal: *jv.Value,

    pub fn op(self: @This()) Opcode {
        return self;
    }
};

pub fn compile(allocator: std.mem.Allocator, compile_allocator: std.mem.Allocator, ast: *const Ast) ![]Instr {
    var instrs = try std.ArrayList(Instr).initCapacity(allocator, 16);

    switch (ast.*) {
        .identity => try instrs.append(allocator, .nop),
        .array_index => |index| {
            const index_instrs = try compile(allocator, compile_allocator, index);
            defer allocator.free(index_instrs);
            try instrs.append(allocator, .subexp_begin);
            try instrs.appendSlice(allocator, index_instrs);
            try instrs.append(allocator, .subexp_end);
            try instrs.append(allocator, .array_index);
        },
        .object_key => |key| try instrs.append(allocator, .{ .object_key = key }),
        .literal => |value| try instrs.append(allocator, .{ .literal = value }),
        .binary_expr => |binary_expr| {
            const rhs_instrs = try compile(allocator, compile_allocator, binary_expr.rhs);
            defer allocator.free(rhs_instrs);
            const lhs_instrs = try compile(allocator, compile_allocator, binary_expr.lhs);
            defer allocator.free(lhs_instrs);
            try instrs.append(allocator, .subexp_begin);
            try instrs.appendSlice(allocator, rhs_instrs);
            try instrs.append(allocator, .subexp_end);
            try instrs.append(allocator, .subexp_begin);
            try instrs.appendSlice(allocator, lhs_instrs);
            try instrs.append(allocator, .subexp_end);
            try instrs.append(allocator, .add);
        },
    }

    return instrs.toOwnedSlice(allocator);
}
