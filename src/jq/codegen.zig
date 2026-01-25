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

const Codegen = struct {
    instrs: std.ArrayList(Instr),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) !Codegen {
        return .{
            .instrs = try std.ArrayList(Instr).initCapacity(allocator, 16),
            .allocator = allocator,
        };
    }

    fn generate(self: *Codegen, ast: *const Ast) !void {
        switch (ast.*) {
            .identity => try self.emit(.nop),
            .index => |idx| {
                try self.generate(idx.base);
                try self.emit(.subexp_begin);
                try self.generate(idx.index);
                try self.emit(.subexp_end);
                try self.emit(if (idx.is_optional) .index_opt else .index);
            },
            .literal => |idx| try self.emit(.{ .@"const" = idx }),
            .binary_expr => |binary_expr| {
                try self.emit(.subexp_begin);
                try self.generate(binary_expr.rhs);
                try self.emit(.subexp_end);
                try self.emit(.subexp_begin);
                try self.generate(binary_expr.lhs);
                try self.emit(.subexp_end);
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
                try self.emit(op_instr);
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
                try self.emit(.dup);
                try self.generate(and_expr.lhs);
                const jump1_idx = self.pos();
                try self.emit(.{ .jump_unless = 0 });
                try self.emit(.pop);
                try self.generate(and_expr.rhs);
                const jump2_idx = self.pos();
                try self.emit(.{ .jump_unless = 0 });
                try self.emit(.const_true);
                const jump3_idx = self.pos();
                try self.emit(.{ .jump = 0 });
                const l1 = self.pos();
                try self.emit(.const_false);
                const jump4_idx = self.pos();
                const l2 = self.pos();
                try self.emit(.{ .jump = 0 });
                const l3 = self.pos();
                try self.emit(.pop);
                try self.emit(.const_false);
                const l4 = self.pos();

                self.patchLabel(jump1_idx, l3);
                self.patchLabel(jump2_idx, l1);
                self.patchLabel(jump3_idx, l2);
                self.patchLabel(jump4_idx, l4);
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
                try self.emit(.dup);
                try self.generate(or_expr.lhs);
                const jump1_idx = self.pos();
                try self.emit(.{ .jump_unless = 0 });
                try self.emit(.pop);
                try self.emit(.const_true);
                const jump2_idx = self.pos();
                try self.emit(.{ .jump = 0 });
                const l1 = self.pos();
                try self.emit(.pop);
                try self.generate(or_expr.rhs);
                const jump3_idx = self.pos();
                try self.emit(.{ .jump_unless = 0 });
                try self.emit(.const_true);
                const jump4_idx = self.pos();
                try self.emit(.{ .jump = 0 });
                const l2 = self.pos();
                try self.emit(.const_false);
                const l3 = self.pos();

                self.patchLabel(jump1_idx, l1);
                self.patchLabel(jump2_idx, l3);
                self.patchLabel(jump3_idx, l2);
                self.patchLabel(jump4_idx, l3);
            },
            .pipe => |pipe_expr| {
                try self.generate(pipe_expr.lhs);
                try self.generate(pipe_expr.rhs);
            },
            .comma => |comma_expr| {
                //     FORK l1
                //     <lhs>
                //     JUMP l2
                // l1: <rhs>
                // l2:
                const fork_index = self.pos();
                try self.emit(.{ .fork = 0 });
                try self.generate(comma_expr.lhs);
                const jump_index = self.pos();
                try self.emit(.{ .jump = 0 });
                const l1 = self.pos();
                try self.generate(comma_expr.rhs);
                const l2 = self.pos();
                self.patchLabel(fork_index, l1);
                self.patchLabel(jump_index, l2);
            },
        }
    }

    fn toOwnedSlice(self: *Codegen) ![]Instr {
        return self.instrs.toOwnedSlice(self.allocator);
    }

    fn emit(self: *Codegen, instr: Instr) !void {
        try self.instrs.append(self.allocator, instr);
    }

    fn pos(self: *const Codegen) usize {
        return self.instrs.items.len;
    }

    fn patchLabel(self: *Codegen, index: usize, target: usize) void {
        const offset = target - index;
        self.instrs.items[index] = switch (self.instrs.items[index]) {
            .jump => .{ .jump = offset },
            .jump_unless => .{ .jump_unless = offset },
            .fork => .{ .fork = offset },
            else => unreachable,
        };
    }
};

pub fn codegen(allocator: std.mem.Allocator, ast: *const Ast) ![]Instr {
    var gen = try Codegen.init(allocator);
    try gen.generate(ast);
    try gen.emit(.ret);
    return gen.toOwnedSlice();
}
