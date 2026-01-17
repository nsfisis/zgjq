const std = @import("std");
const jv = @import("../jv.zig");
const Token = @import("./tokenize.zig").Token;

pub const ParseError = error{
    UnexpectedEnd,
    InvalidQuery,
};

pub const AstKind = enum {
    identity,
    array_index,
    literal,
};

pub const Ast = union(AstKind) {
    identity,
    array_index: *Ast,
    literal: *jv.Value,

    pub fn kind(self: @This()) AstKind {
        return self;
    }
};

pub fn parse(allocator: std.mem.Allocator, tokens: []const Token) !*Ast {
    if (tokens.len < 2) {
        return error.InvalidQuery;
    }

    var i: usize = 0;
    const t1 = tokens[i];
    if (t1.kind() != .dot) {
        return error.InvalidQuery;
    }
    i += 1;
    const t2 = tokens[i];

    if (t2.kind() == .end) {
        const root = try allocator.create(Ast);
        root.* = .identity;
        return root;
    }

    if (t2.kind() != .bracket_left) {
        return error.InvalidQuery;
    }

    i += 1;
    if (tokens.len < 5) {
        return error.UnexpectedEnd;
    }
    const t3 = tokens[i];
    i += 1;
    const t4 = tokens[i];
    i += 1;
    const t5 = tokens[i];

    if (t3.kind() != .number) {
        return error.InvalidQuery;
    }
    if (t4.kind() != .bracket_right) {
        return error.InvalidQuery;
    }
    if (t5.kind() != .end) {
        return error.InvalidQuery;
    }

    const index_value = try allocator.create(jv.Value);
    index_value.* = .{
        .integer = t3.number,
    };
    const index_node = try allocator.create(Ast);
    index_node.* = .{
        .literal = index_value,
    };
    const root = try allocator.create(Ast);
    root.* = .{
        .array_index = index_node,
    };
    return root;
}
