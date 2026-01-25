const std = @import("std");
const jv = @import("../jv.zig");
const Ast = @import("./parse.zig").Ast;
const BinaryOp = @import("./parse.zig").BinaryOp;

pub const ConstIndex = enum(u32) { _ };

pub const Opcode = enum {
    nop,
    ret,
    jump,
    jump_unless,
    fork,
    dup,
    pop,
    subexp_begin,
    subexp_end,
    index,
    index_opt,
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
    const_true,
    const_false,
};

pub const Instr = union(Opcode) {
    const Self = @This();

    nop,
    ret,
    jump: usize,
    jump_unless: usize,
    fork: usize,
    dup,
    pop,
    subexp_begin,
    subexp_end,
    index,
    index_opt,
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
    const_true,
    const_false,

    pub fn op(self: Self) Opcode {
        return self;
    }
};

fn compileExpr(allocator: std.mem.Allocator, compile_allocator: std.mem.Allocator, ast: *const Ast) ![]Instr {
    var instrs = try std.ArrayList(Instr).initCapacity(allocator, 16);

    switch (ast.*) {
        .identity => try instrs.append(allocator, .nop),
        .index => |idx| {
            const base_instrs = try compileExpr(allocator, compile_allocator, idx.base);
            defer allocator.free(base_instrs);
            const index_instrs = try compileExpr(allocator, compile_allocator, idx.index);
            defer allocator.free(index_instrs);
            try instrs.appendSlice(allocator, base_instrs);
            try instrs.append(allocator, .subexp_begin);
            try instrs.appendSlice(allocator, index_instrs);
            try instrs.append(allocator, .subexp_end);
            try instrs.append(allocator, if (idx.is_optional) .index_opt else .index);
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
        .and_expr => |and_expr| {
            //     DUP
            //     <lhs>
            //     JUMP_UNLESS l3
            //     POP
            //     <rhs>
            //     JUMP_UNLESS l1
            //     CONST_TRUE
            //     JUMP l2
            // l1: CONST_FALSE
            // l2: JUMP l4
            // l3: POP
            //     CONST_FALSE
            // l4:
            const lhs_instrs = try compileExpr(allocator, compile_allocator, and_expr.lhs);
            defer allocator.free(lhs_instrs);
            const rhs_instrs = try compileExpr(allocator, compile_allocator, and_expr.rhs);
            defer allocator.free(rhs_instrs);

            try instrs.append(allocator, .dup);
            try instrs.appendSlice(allocator, lhs_instrs);
            const jump1_idx = instrs.items.len;
            try instrs.append(allocator, .{ .jump_unless = 0 });
            try instrs.append(allocator, .pop);
            try instrs.appendSlice(allocator, rhs_instrs);
            const jump2_idx = instrs.items.len;
            try instrs.append(allocator, .{ .jump_unless = 0 });
            try instrs.append(allocator, .const_true);
            const jump3_idx = instrs.items.len;
            try instrs.append(allocator, .{ .jump = 0 });
            const l1 = instrs.items.len;
            try instrs.append(allocator, .const_false);
            const jump4_idx = instrs.items.len;
            const l2 = instrs.items.len;
            try instrs.append(allocator, .{ .jump = 0 });
            const l3 = instrs.items.len;
            try instrs.append(allocator, .pop);
            try instrs.append(allocator, .const_false);
            const l4 = instrs.items.len;

            instrs.items[jump1_idx] = .{ .jump_unless = l3 - jump1_idx };
            instrs.items[jump2_idx] = .{ .jump_unless = l1 - jump2_idx };
            instrs.items[jump3_idx] = .{ .jump = l2 - jump3_idx };
            instrs.items[jump4_idx] = .{ .jump = l4 - jump4_idx };
        },
        .or_expr => |or_expr| {
            //     DUP
            //     <lhs>
            //     JUMP_UNLESS l1
            //     POP
            //     CONST_TRUE
            //     JUMP l3
            // l1: POP
            //     <rhs>
            //     JUMP_UNLESS l2
            //     CONST_TRUE
            //     JUMP l3
            // l2: CONST_FALSE
            // l3:
            const lhs_instrs = try compileExpr(allocator, compile_allocator, or_expr.lhs);
            defer allocator.free(lhs_instrs);
            const rhs_instrs = try compileExpr(allocator, compile_allocator, or_expr.rhs);
            defer allocator.free(rhs_instrs);

            try instrs.append(allocator, .dup);
            try instrs.appendSlice(allocator, lhs_instrs);
            const jump1_idx = instrs.items.len;
            try instrs.append(allocator, .{ .jump_unless = 0 });
            try instrs.append(allocator, .pop);
            try instrs.append(allocator, .const_true);
            const jump2_idx = instrs.items.len;
            try instrs.append(allocator, .{ .jump = 0 });
            const l1 = instrs.items.len;
            try instrs.append(allocator, .pop);
            try instrs.appendSlice(allocator, rhs_instrs);
            const jump3_idx = instrs.items.len;
            try instrs.append(allocator, .{ .jump_unless = 0 });
            try instrs.append(allocator, .const_true);
            const jump4_idx = instrs.items.len;
            try instrs.append(allocator, .{ .jump = 0 });
            const l2 = instrs.items.len;
            try instrs.append(allocator, .const_false);
            const l3 = instrs.items.len;

            instrs.items[jump1_idx] = .{ .jump_unless = l1 - jump1_idx };
            instrs.items[jump2_idx] = .{ .jump = l3 - jump2_idx };
            instrs.items[jump3_idx] = .{ .jump_unless = l2 - jump3_idx };
            instrs.items[jump4_idx] = .{ .jump = l3 - jump4_idx };
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
