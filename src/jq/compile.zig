const std = @import("std");
const jv = @import("../jv.zig");
const Ast = @import("./parse.zig").Ast;

pub const Opcode = enum {
    nop,
    ret,
    subexp_begin,
    subexp_end,
    array_index,
    add,
    object_key,
    literal,
};

pub const Instr = union(Opcode) {
    nop,
    ret,
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

fn compileExpr(allocator: std.mem.Allocator, compile_allocator: std.mem.Allocator, ast: *const Ast) ![]Instr {
    var instrs = try std.ArrayList(Instr).initCapacity(allocator, 16);

    switch (ast.*) {
        .identity => try instrs.append(allocator, .nop),
        .array_index => |index| {
            const index_instrs = try compileExpr(allocator, compile_allocator, index);
            defer allocator.free(index_instrs);
            try instrs.append(allocator, .subexp_begin);
            try instrs.appendSlice(allocator, index_instrs);
            try instrs.append(allocator, .subexp_end);
            try instrs.append(allocator, .array_index);
        },
        .object_key => |key| try instrs.append(allocator, .{ .object_key = key }),
        .literal => |value| try instrs.append(allocator, .{ .literal = value }),
        .binary_expr => |binary_expr| {
            const rhs_instrs = try compileExpr(allocator, compile_allocator, binary_expr.rhs);
            defer allocator.free(rhs_instrs);
            const lhs_instrs = try compileExpr(allocator, compile_allocator, binary_expr.lhs);
            defer allocator.free(lhs_instrs);
            try instrs.append(allocator, .subexp_begin);
            try instrs.appendSlice(allocator, rhs_instrs);
            try instrs.append(allocator, .subexp_end);
            try instrs.append(allocator, .subexp_begin);
            try instrs.appendSlice(allocator, lhs_instrs);
            try instrs.append(allocator, .subexp_end);
            try instrs.append(allocator, .add);
        },
        .pipe => |pipe_expr| {
            const lhs_instrs = try compileExpr(allocator, compile_allocator, pipe_expr.lhs);
            defer allocator.free(lhs_instrs);
            const rhs_instrs = try compileExpr(allocator, compile_allocator, pipe_expr.rhs);
            defer allocator.free(rhs_instrs);
            try instrs.appendSlice(allocator, lhs_instrs);
            try instrs.appendSlice(allocator, rhs_instrs);
        },
    }

    return instrs.toOwnedSlice(allocator);
}

pub fn compile(allocator: std.mem.Allocator, compile_allocator: std.mem.Allocator, ast: *const Ast) ![]Instr {
    var instrs = try std.ArrayList(Instr).initCapacity(allocator, 16);
    const expr_instrs = try compileExpr(allocator, compile_allocator, ast);
    defer allocator.free(expr_instrs);
    try instrs.appendSlice(allocator, expr_instrs);
    try instrs.append(allocator, .ret);
    return instrs.toOwnedSlice(allocator);
}
