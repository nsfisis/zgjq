const std = @import("std");
const Token = @import("./tokenize.zig").Token;

pub const ParseError = error{
    UnexpectedEnd,
    InvalidQuery,
};

pub const AstKind = enum {
    identity,
};

pub const Ast = struct {
    kind: AstKind,
};

pub fn parse(allocator: std.mem.Allocator, tokens: []const Token) !*Ast {
    if (tokens.len != 2) {
        return ParseError.InvalidQuery;
    }
    const t1 = tokens[0];
    const t2 = tokens[1];
    if (t1.kind != .identity) {
        return ParseError.InvalidQuery;
    }
    if (t2.kind != .end) {
        return ParseError.UnexpectedEnd;
    }

    const root = try allocator.create(Ast);
    root.kind = .identity;
    return root;
}
