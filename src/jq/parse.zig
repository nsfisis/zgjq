const std = @import("std");
const jv = @import("../jv.zig");
const ConstIndex = @import("./constant_table.zig").ConstIndex;
const Token = @import("./tokenize.zig").Token;
const TokenKind = @import("./tokenize.zig").TokenKind;

pub const ParseError = error{
    UnexpectedEnd,
    InvalidQuery,
};

pub const AstKind = enum {
    identity,
    index,
    literal,
    binary_expr,
    or_expr,
    and_expr,
    pipe,
    comma,
    construct_array,
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
    index: struct { base: *Ast, index: *Ast, is_optional: bool },
    literal: ConstIndex,
    binary_expr: struct { op: BinaryOp, lhs: *Ast, rhs: *Ast },
    or_expr: struct { lhs: *Ast, rhs: *Ast },
    and_expr: struct { lhs: *Ast, rhs: *Ast },
    pipe: struct { lhs: *Ast, rhs: *Ast },
    comma: struct { lhs: *Ast, rhs: *Ast },
    construct_array: struct { items: *Ast },

    pub fn kind(self: @This()) AstKind {
        return self;
    }
};

const TokenStream = struct {
    const Self = @This();

    tokens: []const Token,
    current_position: usize,

    fn init(tokens: []const Token) Self {
        return .{
            .tokens = tokens,
            .current_position = 0,
        };
    }

    fn next(self: *Self) ParseError!Token {
        if (self.current_position >= self.tokens.len) {
            return error.UnexpectedEnd;
        }
        const token = self.tokens[self.current_position];
        self.current_position += 1;
        return token;
    }

    fn peek(self: *Self) ParseError!Token {
        if (self.current_position >= self.tokens.len) {
            return error.UnexpectedEnd;
        }
        return self.tokens[self.current_position];
    }

    fn expect(self: *Self, expected: TokenKind) ParseError!Token {
        const token = try self.next();
        if (token.kind() != expected) {
            return error.InvalidQuery;
        }
        return token;
    }

    fn consumeIf(self: *Self, expected: TokenKind) bool {
        if (self.current_position >= self.tokens.len) {
            return false;
        }
        if (self.tokens[self.current_position].kind() == expected) {
            self.current_position += 1;
            return true;
        }
        return false;
    }
};

const Parser = struct {
    const Self = @This();
    const Error = ParseError || std.mem.Allocator.Error;

    allocator: std.mem.Allocator,
    compile_allocator: std.mem.Allocator,
    tokens: *TokenStream,
    constants: *std.ArrayList(jv.Value),

    fn parseProgram(self: *Self) Error!*Ast {
        const ret = try self.parseBody();
        _ = try self.tokens.expect(.end);
        return ret;
    }

    fn parseBody(self: *Self) Error!*Ast {
        return self.parseQuery();
    }

    fn parseQuery(self: *Self) Error!*Ast {
        return self.parseQuery2();
    }

    fn parseQuery2(self: *Self) Error!*Ast {
        var lhs = try self.parseQuery3();
        while (self.tokens.consumeIf(.pipe)) {
            const rhs = try self.parseQuery3();
            const ast = try self.compile_allocator.create(Ast);
            ast.* = .{ .pipe = .{
                .lhs = lhs,
                .rhs = rhs,
            } };
            lhs = ast;
        }
        return lhs;
    }

    fn parseQuery3(self: *Self) Error!*Ast {
        var lhs = try self.parseExpr();
        while (self.tokens.consumeIf(.comma)) {
            const rhs = try self.parseExpr();
            const ast = try self.compile_allocator.create(Ast);
            ast.* = .{ .comma = .{
                .lhs = lhs,
                .rhs = rhs,
            } };
            lhs = ast;
        }
        return lhs;
    }

    fn parseExpr(self: *Self) Error!*Ast {
        var lhs = try self.parseExpr2();
        while (self.tokens.consumeIf(.slash_slash)) {
            const rhs = try self.parseExpr2();
            const ast = try self.compile_allocator.create(Ast);
            ast.* = .{ .binary_expr = .{
                .op = .alt,
                .lhs = lhs,
                .rhs = rhs,
            } };
            lhs = ast;
        }
        return lhs;
    }

    fn parseExpr2(self: *Self) Error!*Ast {
        const lhs = try self.parseExpr3();
        const token = self.tokens.peek() catch return lhs;
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
        _ = try self.tokens.next();
        const rhs = try self.parseExpr3();
        const ast = try self.compile_allocator.create(Ast);
        ast.* = .{ .binary_expr = .{
            .op = op,
            .lhs = lhs,
            .rhs = rhs,
        } };
        return ast;
    }

    fn parseExpr3(self: *Self) Error!*Ast {
        const lhs = try self.parseExpr4();
        if (!self.tokens.consumeIf(.keyword_or)) {
            return lhs;
        }
        const rhs = try self.parseExpr4();
        const ast = try self.compile_allocator.create(Ast);
        ast.* = .{ .or_expr = .{
            .lhs = lhs,
            .rhs = rhs,
        } };
        return ast;
    }

    fn parseExpr4(self: *Self) Error!*Ast {
        const lhs = try self.parseExpr5();
        if (!self.tokens.consumeIf(.keyword_and)) {
            return lhs;
        }
        const rhs = try self.parseExpr5();
        const ast = try self.compile_allocator.create(Ast);
        ast.* = .{ .and_expr = .{
            .lhs = lhs,
            .rhs = rhs,
        } };
        return ast;
    }

    fn parseExpr5(self: *Self) Error!*Ast {
        const lhs = try self.parseExpr6();
        const token = self.tokens.peek() catch return lhs;
        const op: BinaryOp = switch (token.kind()) {
            .equal_equal => .eq,
            .not_equal => .ne,
            .less_than => .lt,
            .greater_than => .gt,
            .less_than_equal => .le,
            .greater_than_equal => .ge,
            else => return lhs,
        };
        _ = try self.tokens.next();
        const rhs = try self.parseExpr6();
        const ast = try self.compile_allocator.create(Ast);
        ast.* = .{ .binary_expr = .{
            .op = op,
            .lhs = lhs,
            .rhs = rhs,
        } };
        return ast;
    }

    fn parseExpr6(self: *Self) Error!*Ast {
        var lhs = try self.parseExpr7();
        while (true) {
            const token = self.tokens.peek() catch return lhs;
            const op: BinaryOp = switch (token.kind()) {
                .plus => .add,
                .minus => .sub,
                else => return lhs,
            };
            _ = try self.tokens.next();
            const rhs = try self.parseExpr7();
            const ast = try self.compile_allocator.create(Ast);
            ast.* = .{ .binary_expr = .{
                .op = op,
                .lhs = lhs,
                .rhs = rhs,
            } };
            lhs = ast;
        }
    }

    fn parseExpr7(self: *Self) Error!*Ast {
        var lhs = try self.parseTerm();
        while (true) {
            const token = self.tokens.peek() catch return lhs;
            const op: BinaryOp = switch (token.kind()) {
                .asterisk => .mul,
                .slash => .div,
                .percent => .mod,
                else => return lhs,
            };
            _ = try self.tokens.next();
            const rhs = try self.parseTerm();
            const ast = try self.compile_allocator.create(Ast);
            ast.* = .{ .binary_expr = .{
                .op = op,
                .lhs = lhs,
                .rhs = rhs,
            } };
            lhs = ast;
        }
    }

    fn parseTerm(self: *Self) Error!*Ast {
        var result = try self.parsePrimary();
        while (true) {
            const token = self.tokens.peek() catch return result;
            if (token.kind() == .bracket_left) {
                result = try self.parseSuffix(result);
            } else {
                break;
            }
        }
        return result;
    }

    fn parsePrimary(self: *Self) Error!*Ast {
        const first_token = try self.tokens.peek();
        switch (first_token) {
            .keyword_null => {
                _ = try self.tokens.next();
                const null_node = try self.compile_allocator.create(Ast);
                null_node.* = .{ .literal = .null };
                return null_node;
            },
            .keyword_false => {
                _ = try self.tokens.next();
                const false_node = try self.compile_allocator.create(Ast);
                false_node.* = .{ .literal = .false };
                return false_node;
            },
            .keyword_true => {
                _ = try self.tokens.next();
                const true_node = try self.compile_allocator.create(Ast);
                true_node.* = .{ .literal = .true };
                return true_node;
            },
            .number => |f| {
                _ = try self.tokens.next();
                const i: i64 = @intFromFloat(f);
                if (@as(f64, @floatFromInt(i)) == f) {
                    try self.constants.append(self.allocator, .{ .integer = i });
                } else {
                    try self.constants.append(self.allocator, .{ .float = f });
                }
                const idx: ConstIndex = @enumFromInt(self.constants.items.len - 1);
                const number_node = try self.compile_allocator.create(Ast);
                number_node.* = .{ .literal = idx };
                return number_node;
            },
            .string => |s| {
                _ = try self.tokens.next();
                try self.constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, s) });
                const idx: ConstIndex = @enumFromInt(self.constants.items.len - 1);
                const string_node = try self.compile_allocator.create(Ast);
                string_node.* = .{ .literal = idx };
                return string_node;
            },
            .dot => {
                _ = try self.tokens.next();
                const ast = try self.compile_allocator.create(Ast);
                ast.* = .identity;
                return ast;
            },
            .bracket_left => {
                _ = try self.tokens.next();
                if (self.tokens.consumeIf(.bracket_right)) {
                    const array_node = try self.compile_allocator.create(Ast);
                    array_node.* = .{ .literal = .empty_array };
                    return array_node;
                } else {
                    const inner_query = try self.parseQuery();
                    _ = try self.tokens.expect(.bracket_right);
                    const array_node = try self.compile_allocator.create(Ast);
                    array_node.* = .{ .construct_array = .{ .items = inner_query } };
                    return array_node;
                }
            },
            .brace_left => {
                _ = try self.tokens.next();
                _ = try self.tokens.expect(.brace_right);
                try self.constants.append(self.allocator, .{ .object = jv.Object.init(self.allocator) });
                const idx: ConstIndex = @enumFromInt(self.constants.items.len - 1);
                const object_node = try self.compile_allocator.create(Ast);
                object_node.* = .{ .literal = idx };
                return object_node;
            },
            .field => |name| {
                _ = try self.tokens.next();
                const is_optional = self.tokens.consumeIf(.question);
                const base_ast = try self.compile_allocator.create(Ast);
                base_ast.* = .identity;
                try self.constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, name) });
                const idx: ConstIndex = @enumFromInt(self.constants.items.len - 1);
                const key_ast = try self.compile_allocator.create(Ast);
                key_ast.* = .{ .literal = idx };
                const ast = try self.compile_allocator.create(Ast);
                ast.* = .{ .index = .{ .base = base_ast, .index = key_ast, .is_optional = is_optional } };
                return ast;
            },
            else => return error.InvalidQuery,
        }
    }

    fn parseSuffix(self: *Self, base: *Ast) Error!*Ast {
        _ = try self.tokens.expect(.bracket_left);
        const index_expr = try self.parseExpr();
        _ = try self.tokens.expect(.bracket_right);

        const is_optional = self.tokens.consumeIf(.question);

        const ast = try self.compile_allocator.create(Ast);
        ast.* = .{ .index = .{ .base = base, .index = index_expr, .is_optional = is_optional } };
        return ast;
    }
};

pub fn parse(allocator: std.mem.Allocator, compile_allocator: std.mem.Allocator, tokens: []const Token, constants: *std.ArrayList(jv.Value)) !*Ast {
    var token_stream = TokenStream.init(tokens);
    var parser = Parser{
        .allocator = allocator,
        .compile_allocator = compile_allocator,
        .tokens = &token_stream,
        .constants = constants,
    };
    return try parser.parseProgram();
}
