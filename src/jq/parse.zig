const std = @import("std");
const jv = @import("../jv.zig");
const Token = @import("./tokenize.zig").Token;
const TokenKind = @import("./tokenize.zig").TokenKind;

pub const ParseError = error{
    UnexpectedEnd,
    InvalidQuery,
};

pub const AstKind = enum {
    identity,
    array_index,
    object_key,
    literal,
};

pub const Ast = union(AstKind) {
    identity,
    array_index: *Ast,
    object_key: []const u8,
    literal: *jv.Value,

    pub fn kind(self: @This()) AstKind {
        return self;
    }
};

pub const TokenStream = struct {
    const Self = @This();

    tokens: []const Token,
    current_position: usize,

    pub fn init(tokens: []const Token) Self {
        return .{
            .tokens = tokens,
            .current_position = 0,
        };
    }

    pub fn next(self: *Self) ParseError!Token {
        if (self.current_position >= self.tokens.len) {
            return error.UnexpectedEnd;
        }
        const token = self.tokens[self.current_position];
        self.current_position += 1;
        return token;
    }

    pub fn peek(self: *Self) ParseError!Token {
        if (self.current_position >= self.tokens.len) {
            return error.UnexpectedEnd;
        }
        return self.tokens[self.current_position];
    }

    pub fn expect(self: *Self, expected: TokenKind) ParseError!Token {
        const token = try self.next();
        if (token.kind() != expected) {
            return error.InvalidQuery;
        }
        return token;
    }
};

pub fn parse(allocator: std.mem.Allocator, tokens: []const Token) !*Ast {
    var token_stream = TokenStream.init(tokens);
    return parseQuery(allocator, &token_stream);
}

// GRAMMAR
//   query := filter
fn parseQuery(allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    const result = try parseFilter(allocator, tokens);
    _ = try tokens.expect(.end);
    return result;
}

// GRAMMAR
//   filter := "." accessor?
fn parseFilter(allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    _ = try tokens.expect(.dot);

    const next_token = try tokens.peek();

    if (next_token.kind() == .end) {
        const ast = try allocator.create(Ast);
        ast.* = .identity;
        return ast;
    }

    return parseAccessor(allocator, tokens);
}

// GRAMMAR
//   accessor := field_access | index_access
fn parseAccessor(allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    const token = try tokens.peek();

    if (token.kind() == .identifier) {
        return parseFieldAccess(allocator, tokens);
    }
    if (token.kind() == .bracket_left) {
        return parseIndexAccess(allocator, tokens);
    }

    return error.InvalidQuery;
}

// GRAMMAR
//   field_access := IDENTIFIER
fn parseFieldAccess(allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    const token = try tokens.expect(.identifier);
    const ast = try allocator.create(Ast);
    ast.* = .{ .object_key = token.identifier };
    return ast;
}

// GRAMMAR
//   index_access := "[" NUMBER "]"
fn parseIndexAccess(allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    _ = try tokens.expect(.bracket_left);
    const index_token = try tokens.expect(.number);
    _ = try tokens.expect(.bracket_right);

    const index_value = try allocator.create(jv.Value);
    index_value.* = .{ .integer = index_token.number };
    const index_node = try allocator.create(Ast);
    index_node.* = .{ .literal = index_value };
    const ast = try allocator.create(Ast);
    ast.* = .{ .array_index = index_node };
    return ast;
}
