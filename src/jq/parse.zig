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
    binary_expr,
    pipe,
    comma,
};

pub const BinaryOp = enum {
    alt,
    assign,
    update,
    alt_assign,
    add_assign,
    sub_assign,
    mul_assign,
    div_assign,
    mod_assign,
    @"or",
    @"and",
    eq,
    ne,
    lt,
    gt,
    le,
    ge,
    add,
    sub,
    mul,
    div,
    mod,
};

pub const Ast = union(AstKind) {
    identity,
    array_index: struct { base: *Ast, index: *Ast },
    object_key: []const u8,
    literal: *jv.Value,
    binary_expr: struct { op: BinaryOp, lhs: *Ast, rhs: *Ast },
    pipe: struct { lhs: *Ast, rhs: *Ast },
    comma: struct { lhs: *Ast, rhs: *Ast },

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

pub fn parse(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: []const Token) !*Ast {
    var token_stream = TokenStream.init(tokens);
    return parseQuery(allocator, parse_allocator, &token_stream);
}

fn parseProgram(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    return parseBody(allocator, parse_allocator, tokens);
}

fn parseBody(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    return parseQuery(allocator, parse_allocator, tokens);
}

fn parseQuery(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    return parseQuery2(allocator, parse_allocator, tokens);
}

fn parseQuery2(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    var lhs = try parseQuery3(allocator, parse_allocator, tokens);
    while (true) {
        const token = tokens.peek() catch break;
        if (token.kind() == .pipe) {
            _ = try tokens.next();
            const rhs = try parseQuery3(allocator, parse_allocator, tokens);
            const ast = try parse_allocator.create(Ast);
            ast.* = .{ .pipe = .{
                .lhs = lhs,
                .rhs = rhs,
            } };
            lhs = ast;
        } else {
            break;
        }
    }
    _ = try tokens.expect(.end);
    return lhs;
}

fn parseQuery3(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    var lhs = try parseExpr(allocator, parse_allocator, tokens);
    while (true) {
        const token = tokens.peek() catch return lhs;
        if (token.kind() == .comma) {
            _ = try tokens.next();
            const rhs = try parseExpr(allocator, parse_allocator, tokens);
            const ast = try parse_allocator.create(Ast);
            ast.* = .{ .comma = .{
                .lhs = lhs,
                .rhs = rhs,
            } };
            lhs = ast;
        } else {
            break;
        }
    }
    return lhs;
}

fn parseExpr(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    var lhs = try parseExpr2(allocator, parse_allocator, tokens);
    while (true) {
        const token = try tokens.peek();
        if (token.kind() == .slash_slash) {
            _ = try tokens.next();
            const rhs = try parseExpr2(allocator, parse_allocator, tokens);
            const ast = try parse_allocator.create(Ast);
            ast.* = .{ .binary_expr = .{
                .op = .alt,
                .lhs = lhs,
                .rhs = rhs,
            } };
            lhs = ast;
        } else {
            break;
        }
    }
    return lhs;
}

fn parseExpr2(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    const lhs = try parseExpr3(allocator, parse_allocator, tokens);
    const token = tokens.peek() catch return lhs;
    const op: BinaryOp = switch (token.kind()) {
        .equal => .assign,
        .pipe_equal => .update,
        .slash_slash_equal => .alt_assign,
        .plus_equal => .add_assign,
        .minus_equal => .sub_assign,
        .asterisk_equal => .mul_assign,
        .slash_equal => .div_assign,
        .percent_equal => .mod_assign,
        else => return lhs,
    };
    _ = try tokens.next();
    const rhs = try parseExpr3(allocator, parse_allocator, tokens);
    const ast = try parse_allocator.create(Ast);
    ast.* = .{ .binary_expr = .{
        .op = op,
        .lhs = lhs,
        .rhs = rhs,
    } };
    return ast;
}

fn parseExpr3(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    const lhs = try parseExpr4(allocator, parse_allocator, tokens);
    const token = tokens.peek() catch return lhs;
    if (token.kind() != .keyword_or) {
        return lhs;
    }
    _ = try tokens.next();
    const rhs = try parseExpr4(allocator, parse_allocator, tokens);
    const ast = try parse_allocator.create(Ast);
    ast.* = .{ .binary_expr = .{
        .op = .@"or",
        .lhs = lhs,
        .rhs = rhs,
    } };
    return ast;
}

fn parseExpr4(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    const lhs = try parseExpr5(allocator, parse_allocator, tokens);
    const token = tokens.peek() catch return lhs;
    if (token.kind() != .keyword_and) {
        return lhs;
    }
    _ = try tokens.next();
    const rhs = try parseExpr5(allocator, parse_allocator, tokens);
    const ast = try parse_allocator.create(Ast);
    ast.* = .{ .binary_expr = .{
        .op = .@"and",
        .lhs = lhs,
        .rhs = rhs,
    } };
    return ast;
}

fn parseExpr5(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    const lhs = try parseExpr6(allocator, parse_allocator, tokens);
    const token = tokens.peek() catch return lhs;
    const op: BinaryOp = switch (token.kind()) {
        .equal_equal => .eq,
        .not_equal => .ne,
        .less_than => .lt,
        .greater_than => .gt,
        .less_than_equal => .le,
        .greater_than_equal => .ge,
        else => return lhs,
    };
    _ = try tokens.next();
    const rhs = try parseExpr6(allocator, parse_allocator, tokens);
    const ast = try parse_allocator.create(Ast);
    ast.* = .{ .binary_expr = .{
        .op = op,
        .lhs = lhs,
        .rhs = rhs,
    } };
    return ast;
}

fn parseExpr6(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    var lhs = try parseExpr7(allocator, parse_allocator, tokens);
    while (true) {
        const token = tokens.peek() catch return lhs;
        const op: BinaryOp = switch (token.kind()) {
            .plus => .add,
            .minus => .sub,
            else => return lhs,
        };
        _ = try tokens.next();
        const rhs = try parseExpr7(allocator, parse_allocator, tokens);
        const ast = try parse_allocator.create(Ast);
        ast.* = .{ .binary_expr = .{
            .op = op,
            .lhs = lhs,
            .rhs = rhs,
        } };
        lhs = ast;
    }
}

fn parseExpr7(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    var lhs = try parseTerm(allocator, parse_allocator, tokens);
    while (true) {
        const token = tokens.peek() catch return lhs;
        const op: BinaryOp = switch (token.kind()) {
            .asterisk => .mul,
            .slash => .div,
            .percent => .mod,
            else => return lhs,
        };
        _ = try tokens.next();
        const rhs = try parseTerm(allocator, parse_allocator, tokens);
        const ast = try parse_allocator.create(Ast);
        ast.* = .{ .binary_expr = .{
            .op = op,
            .lhs = lhs,
            .rhs = rhs,
        } };
        lhs = ast;
    }
}

fn parseTerm(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    var result = try parsePrimary(allocator, parse_allocator, tokens);
    while (true) {
        const token = tokens.peek() catch return result;
        if (token.kind() == .bracket_left) {
            result = try parseSuffix(allocator, parse_allocator, tokens, result);
        } else {
            break;
        }
    }
    return result;
}

fn parsePrimary(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream) !*Ast {
    const first_token = try tokens.peek();
    switch (first_token) {
        .keyword_null => {
            _ = try tokens.next();
            const null_value = try allocator.create(jv.Value);
            null_value.* = .null;
            const null_node = try parse_allocator.create(Ast);
            null_node.* = .{ .literal = null_value };
            return null_node;
        },
        .keyword_true => {
            _ = try tokens.next();
            const true_value = try allocator.create(jv.Value);
            true_value.* = .{ .bool = true };
            const true_node = try parse_allocator.create(Ast);
            true_node.* = .{ .literal = true_value };
            return true_node;
        },
        .keyword_false => {
            _ = try tokens.next();
            const false_value = try allocator.create(jv.Value);
            false_value.* = .{ .bool = false };
            const false_node = try parse_allocator.create(Ast);
            false_node.* = .{ .literal = false_value };
            return false_node;
        },
        .number => |f| {
            _ = try tokens.next();
            const number_value = try allocator.create(jv.Value);
            const i: i64 = @intFromFloat(f);
            if (@as(f64, @floatFromInt(i)) == f) {
                number_value.* = .{ .integer = i };
            } else {
                number_value.* = .{ .float = f };
            }
            const number_node = try parse_allocator.create(Ast);
            number_node.* = .{ .literal = number_value };
            return number_node;
        },
        .string => |s| {
            _ = try tokens.next();
            const string_value = try allocator.create(jv.Value);
            string_value.* = .{ .string = try allocator.dupe(u8, s) };
            const string_node = try parse_allocator.create(Ast);
            string_node.* = .{ .literal = string_value };
            return string_node;
        },
        .dot => {
            _ = try tokens.next();
            const ast = try parse_allocator.create(Ast);
            ast.* = .identity;
            return ast;
        },
        .field => |name| {
            _ = try tokens.next();
            const ast = try parse_allocator.create(Ast);
            ast.* = .{ .object_key = try allocator.dupe(u8, name) };
            return ast;
        },
        else => return error.InvalidQuery,
    }
}

fn parseSuffix(allocator: std.mem.Allocator, parse_allocator: std.mem.Allocator, tokens: *TokenStream, base: *Ast) !*Ast {
    _ = try tokens.expect(.bracket_left);
    const index_token = try tokens.expect(.number);
    _ = try tokens.expect(.bracket_right);

    const index_value = try allocator.create(jv.Value);
    index_value.* = .{ .integer = @intFromFloat(index_token.number) };
    const index_node = try parse_allocator.create(Ast);
    index_node.* = .{ .literal = index_value };

    const ast = try parse_allocator.create(Ast);
    ast.* = .{ .array_index = .{ .base = base, .index = index_node } };
    return ast;
}
