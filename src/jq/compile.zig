const std = @import("std");
const Ast = @import("./parse.zig").Ast;

pub const Opcode = enum {
    nop,
    identity,
};

pub const Instr = struct {
    op: Opcode,
};

pub fn compile(allocator: std.mem.Allocator, compile_allocator: std.mem.Allocator, ast: *const Ast) ![]Instr {
    _ = compile_allocator;
    var instrs = try std.array_list.Aligned(Instr, null).initCapacity(allocator, 16);

    switch (ast.kind) {
        .identity => try instrs.append(allocator, .{ .op = .identity }),
    }

    return instrs.toOwnedSlice(allocator);
}
