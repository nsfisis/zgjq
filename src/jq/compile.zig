const std = @import("std");
const jv = @import("../jv.zig");
const Ast = @import("./parse.zig").Ast;
const BinaryOp = @import("./parse.zig").BinaryOp;

pub const ConstIndex = enum(u32) { _ };

pub const Opcode = enum {
    nop,
    ret,
    jump,
    fork,
    subexp_begin,
    subexp_end,
    index,
    add,
    sub,
    mul,
    div,
    mod,
    eq,
    ne,
    lt,
    gt,
    le,
    ge,
    @"const",
};

pub const Instr = union(Opcode) {
    const Self = @This();

    nop,
    ret,
    jump: usize,
    fork: usize,
    subexp_begin,
    subexp_end,
    index,
    add,
    sub,
    mul,
    div,
    mod,
    eq,
    ne,
    lt,
    gt,
    le,
    ge,
    @"const": ConstIndex,

    pub fn op(self: Self) Opcode {
        return self;
    }
};

fn compileExpr(allocator: std.mem.Allocator, compile_allocator: std.mem.Allocator, ast: *const Ast) ![]Instr {
    var instrs = try std.ArrayList(Instr).initCapacity(allocator, 16);

    switch (ast.*) {
        .identity => try instrs.append(allocator, .nop),
        .index => |index| {
            const base_instrs = try compileExpr(allocator, compile_allocator, index.base);
            defer allocator.free(base_instrs);
            const index_instrs = try compileExpr(allocator, compile_allocator, index.index);
            defer allocator.free(index_instrs);
            try instrs.appendSlice(allocator, base_instrs);
            try instrs.append(allocator, .subexp_begin);
            try instrs.appendSlice(allocator, index_instrs);
            try instrs.append(allocator, .subexp_end);
            try instrs.append(allocator, .index);
        },
        .literal => |idx| try instrs.append(allocator, .{ .@"const" = idx }),
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
            const op_instr: Instr = switch (binary_expr.op) {
                .add => .add,
                .sub => .sub,
                .mul => .mul,
                .div => .div,
                .mod => .mod,
                .eq => .eq,
                .ne => .ne,
                .lt => .lt,
                .gt => .gt,
                .le => .le,
                .ge => .ge,
                else => return error.Unimplemented,
            };
            try instrs.append(allocator, op_instr);
        },
        .pipe => |pipe_expr| {
            const lhs_instrs = try compileExpr(allocator, compile_allocator, pipe_expr.lhs);
            defer allocator.free(lhs_instrs);
            const rhs_instrs = try compileExpr(allocator, compile_allocator, pipe_expr.rhs);
            defer allocator.free(rhs_instrs);
            try instrs.appendSlice(allocator, lhs_instrs);
            try instrs.appendSlice(allocator, rhs_instrs);
        },
        .comma => |comma_expr| {
            //     FORK l1
            //     <lhs>
            //     JUMP l2
            // l1: <rhs>
            // l2:
            const lhs_instrs = try compileExpr(allocator, compile_allocator, comma_expr.lhs);
            defer allocator.free(lhs_instrs);
            const rhs_instrs = try compileExpr(allocator, compile_allocator, comma_expr.rhs);
            defer allocator.free(rhs_instrs);
            const fork_index = instrs.items.len;
            try instrs.append(allocator, .{ .fork = 0 });
            try instrs.appendSlice(allocator, lhs_instrs);
            const jump_index = instrs.items.len;
            try instrs.append(allocator, .{ .jump = 0 });
            const l1 = instrs.items.len;
            try instrs.appendSlice(allocator, rhs_instrs);
            const l2 = instrs.items.len;
            instrs.items[fork_index] = .{ .fork = l1 - fork_index };
            instrs.items[jump_index] = .{ .jump = l2 - jump_index };
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
