const std = @import("std");
const jv = @import("../jv.zig");
const Ast = @import("./parse.zig").Ast;

pub const Opcode = enum {
    nop,
    array_index,
    literal,
};

pub const Instr = union(Opcode) {
    nop,
    array_index,
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
            try instrs.appendSlice(allocator, index_instrs);
            try instrs.append(allocator, .array_index);
        },
        .literal => |value| try instrs.append(allocator, .{ .literal = value }),
    }

    return instrs.toOwnedSlice(allocator);
}
