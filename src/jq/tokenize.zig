const std = @import("std");

pub const TokenizeError = error{
    UnexpectedEnd,
    InvalidCharacter,
    InvalidNumber,
};

pub const TokenKind = enum {
    end,

    asterisk,
    asterisk_equal,
    brace_left,
    brace_right,
    bracket_left,
    bracket_right,
    colon,
    comma,
    dollar,
    dot,
    dot_dot,
    equal,
    equal_equal,
    greater_than,
    greater_than_equal,
    less_than,
    less_than_equal,
    minus,
    minus_equal,
    not_equal,
    paren_left,
    paren_right,
    percent,
    percent_equal,
    pipe,
    pipe_equal,
    plus,
    plus_equal,
    question,
    question_slash_slash,
    semicolon,
    slash,
    slash_equal,
    slash_slash,
    slash_slash_equal,

    keyword_and,
    keyword_as,
    keyword_break,
    keyword_catch,
    keyword_def,
    keyword_elif,
    keyword_else,
    keyword_end,
    keyword_false,
    keyword_foreach,
    keyword_if,
    keyword_import,
    keyword_include,
    keyword_label,
    keyword_module,
    keyword_null,
    keyword_or,
    keyword_reduce,
    keyword_then,
    keyword_true,
    keyword_try,

    identifier,
    number,
};

pub const Token = union(TokenKind) {
    end,

    asterisk,
    asterisk_equal,
    brace_left,
    brace_right,
    bracket_left,
    bracket_right,
    colon,
    comma,
    dollar,
    dot,
    dot_dot,
    equal,
    equal_equal,
    greater_than,
    greater_than_equal,
    less_than,
    less_than_equal,
    minus,
    minus_equal,
    not_equal,
    paren_left,
    paren_right,
    percent,
    percent_equal,
    pipe,
    pipe_equal,
    plus,
    plus_equal,
    question,
    question_slash_slash,
    semicolon,
    slash,
    slash_equal,
    slash_slash,
    slash_slash_equal,

    keyword_and,
    keyword_as,
    keyword_break,
    keyword_catch,
    keyword_def,
    keyword_elif,
    keyword_else,
    keyword_end,
    keyword_false,
    keyword_foreach,
    keyword_if,
    keyword_import,
    keyword_include,
    keyword_label,
    keyword_module,
    keyword_null,
    keyword_or,
    keyword_reduce,
    keyword_then,
    keyword_true,
    keyword_try,

    identifier: []const u8,
    number: f64,

    pub fn kind(self: @This()) TokenKind {
        return self;
    }
};

fn peekByte(reader: *std.Io.Reader) error{ReadFailed}!?u8 {
    return reader.peekByte() catch |err| switch (err) {
        error.EndOfStream => null,
        error.ReadFailed => error.ReadFailed,
    };
}

fn takeByteIf(reader: *std.Io.Reader, expected: u8) error{ReadFailed}!bool {
    if (try peekByte(reader) == expected) {
        reader.toss(1);
        return true;
    } else {
        return false;
    }
}

fn skipComment(reader: *std.Io.Reader) error{ReadFailed}!void {
    var is_last_character_unescaped_backslash = false;

    while (true) {
        const c = reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => return,
            error.ReadFailed => return error.ReadFailed,
        };

        if (c == '\n') {
            if (is_last_character_unescaped_backslash) {
                is_last_character_unescaped_backslash = false;
                continue; // comment line continuation
            } else {
                return;
            }
        } else if (c == '\r') {
            // Check CRLF.
            if (try peekByte(reader) == '\n') {
                reader.toss(1);
                if (is_last_character_unescaped_backslash) {
                    is_last_character_unescaped_backslash = false;
                    continue; // comment line continuation
                } else {
                    return;
                }
            }
            is_last_character_unescaped_backslash = false;
            // NOTE: single CR is not treated as line break, as the original jq does.
        } else if (c == '\\') {
            is_last_character_unescaped_backslash = !is_last_character_unescaped_backslash;
        } else {
            is_last_character_unescaped_backslash = false;
        }
    }
}

fn isIdentifierStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentifierContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn tokenizeIdentifier(allocator: std.mem.Allocator, reader: *std.Io.Reader, first: u8) ![]const u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 16);
    try buffer.append(allocator, first);

    while (true) {
        // Read an identifier.
        while (try peekByte(reader)) |c| {
            if (isIdentifierContinue(c)) {
                try buffer.append(allocator, c);
                reader.toss(1);
            } else {
                break;
            }
        }

        // Check namespaced identifier (e.g., "foo::bar").
        const lookahead = reader.peek(3) catch |err| switch (err) {
            error.EndOfStream => break,
            error.ReadFailed => return error.ReadFailed,
        };
        if (lookahead[0] == ':' and lookahead[1] == ':' and isIdentifierStart(lookahead[2])) {
            try buffer.append(allocator, ':');
            try buffer.append(allocator, ':');
            try buffer.append(allocator, lookahead[2]);
            reader.toss(3);
            continue;
        } else {
            break;
        }
    }

    return buffer.toOwnedSlice(allocator);
}

fn tokenizeNumber(allocator: std.mem.Allocator, reader: *std.Io.Reader, first: u8) !f64 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 16);
    try buffer.append(allocator, first);

    // Integer part
    while (try peekByte(reader)) |c| {
        if (std.ascii.isDigit(c)) {
            try buffer.append(allocator, c);
            reader.toss(1);
        } else {
            break;
        }
    }

    // Fractional part
    if (try peekByte(reader) == '.') {
        const lookahead = reader.peek(2) catch |err| switch (err) {
            error.EndOfStream => null,
            error.ReadFailed => return error.ReadFailed,
        };
        if (lookahead) |bytes| {
            if (std.ascii.isDigit(bytes[1])) {
                try buffer.append(allocator, '.');
                reader.toss(1);
                while (try peekByte(reader)) |c| {
                    if (std.ascii.isDigit(c)) {
                        try buffer.append(allocator, c);
                        reader.toss(1);
                    } else {
                        break;
                    }
                }
            }
        }
    }

    // Exponent part
    if (try peekByte(reader)) |c| {
        if (c == 'e' or c == 'E') {
            try buffer.append(allocator, c);
            reader.toss(1);

            // Sign
            if (try peekByte(reader)) |sign| {
                if (sign == '+' or sign == '-') {
                    try buffer.append(allocator, sign);
                    reader.toss(1);
                }
            }

            // Exponent
            var has_exp_digits = false;
            while (try peekByte(reader)) |d| {
                if (std.ascii.isDigit(d)) {
                    try buffer.append(allocator, d);
                    reader.toss(1);
                    has_exp_digits = true;
                } else {
                    break;
                }
            }
            if (!has_exp_digits) {
                return error.InvalidNumber;
            }
        }
    }

    const slice = buffer.toOwnedSlice(allocator) catch return error.OutOfMemory;
    return std.fmt.parseFloat(f64, slice) catch return error.InvalidNumber;
}

fn tryConvertToKeywordToken(identifier: []const u8) ?Token {
    const keywords = .{
        .{ "and", Token.keyword_and },
        .{ "as", Token.keyword_as },
        .{ "break", Token.keyword_break },
        .{ "catch", Token.keyword_catch },
        .{ "def", Token.keyword_def },
        .{ "elif", Token.keyword_elif },
        .{ "else", Token.keyword_else },
        .{ "end", Token.keyword_end },
        .{ "false", Token.keyword_false },
        .{ "foreach", Token.keyword_foreach },
        .{ "if", Token.keyword_if },
        .{ "import", Token.keyword_import },
        .{ "include", Token.keyword_include },
        .{ "label", Token.keyword_label },
        .{ "module", Token.keyword_module },
        .{ "null", Token.keyword_null },
        .{ "or", Token.keyword_or },
        .{ "reduce", Token.keyword_reduce },
        .{ "then", Token.keyword_then },
        .{ "true", Token.keyword_true },
        .{ "try", Token.keyword_try },
    };

    inline for (keywords) |keyword| {
        if (std.mem.eql(u8, identifier, keyword[0])) {
            return keyword[1];
        }
    }
    return null;
}

pub fn tokenize(allocator: std.mem.Allocator, reader: *std.Io.Reader) ![]Token {
    var tokens = try std.ArrayList(Token).initCapacity(allocator, 16);

    while (true) {
        const c = reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            error.ReadFailed => return error.ReadFailed,
        };
        const token: Token = switch (c) {
            ' ', '\t', '\n', '\r' => continue,
            '#' => {
                try skipComment(reader);
                continue;
            },
            '$' => .dollar,
            '%' => if (try takeByteIf(reader, '=')) .percent_equal else .percent,
            '(' => .paren_left,
            ')' => .paren_right,
            '*' => if (try takeByteIf(reader, '=')) .asterisk_equal else .asterisk,
            '+' => if (try takeByteIf(reader, '=')) .plus_equal else .plus,
            ',' => .comma,
            '-' => if (try takeByteIf(reader, '=')) .minus_equal else .minus,
            '.' => if (try takeByteIf(reader, '.')) .dot_dot else .dot,
            '/' => if (try takeByteIf(reader, '/'))
                if (try takeByteIf(reader, '=')) .slash_slash_equal else .slash_slash
            else if (try takeByteIf(reader, '='))
                .slash_equal
            else
                .slash,
            ':' => .colon,
            ';' => .semicolon,
            '<' => if (try takeByteIf(reader, '=')) .less_than_equal else .less_than,
            '=' => if (try takeByteIf(reader, '=')) .equal_equal else .equal,
            '>' => if (try takeByteIf(reader, '=')) .greater_than_equal else .greater_than,
            '!' => if (try takeByteIf(reader, '=')) .not_equal else return error.InvalidCharacter,
            '?' => if (try takeByteIf(reader, '/'))
                if (try takeByteIf(reader, '/')) .question_slash_slash else return error.InvalidCharacter
            else
                .question,
            '[' => .bracket_left,
            ']' => .bracket_right,
            '{' => .brace_left,
            '|' => if (try takeByteIf(reader, '=')) .pipe_equal else .pipe,
            '}' => .brace_right,
            else => blk: {
                if (std.ascii.isDigit(c)) {
                    break :blk .{ .number = try tokenizeNumber(allocator, reader, c) };
                } else if (isIdentifierStart(c)) {
                    const ident = try tokenizeIdentifier(allocator, reader, c);
                    break :blk tryConvertToKeywordToken(ident) orelse Token{ .identifier = ident };
                } else {
                    return error.InvalidCharacter;
                }
            },
        };
        try tokens.append(allocator, token);
    }

    if (tokens.items.len == 0) {
        return error.UnexpectedEnd;
    }

    try tokens.append(allocator, .end);
    return tokens.toOwnedSlice(allocator);
}

test "tokenize symbols" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed(
        \\* *= { } [ ] : , $ . .. = == > >= < <= - -= != ( ) % %=
        \\| |= + += ? ?// ; / /= // //=
    );
    const tokens = try tokenize(allocator.allocator(), &reader);

    const expected = [_]Token{
        .asterisk,
        .asterisk_equal,
        .brace_left,
        .brace_right,
        .bracket_left,
        .bracket_right,
        .colon,
        .comma,
        .dollar,
        .dot,
        .dot_dot,
        .equal,
        .equal_equal,
        .greater_than,
        .greater_than_equal,
        .less_than,
        .less_than_equal,
        .minus,
        .minus_equal,
        .not_equal,
        .paren_left,
        .paren_right,
        .percent,
        .percent_equal,
        .pipe,
        .pipe_equal,
        .plus,
        .plus_equal,
        .question,
        .question_slash_slash,
        .semicolon,
        .slash,
        .slash_equal,
        .slash_slash,
        .slash_slash_equal,
        .end,
    };
    try std.testing.expectEqual(expected.len, tokens.len);
    for (expected, tokens) |e, t| {
        try std.testing.expectEqual(e, t);
    }
}

test "tokenize number" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed("5 123");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(3, tokens.len);
    try std.testing.expectEqual(Token{ .number = 5 }, tokens[0]);
    try std.testing.expectEqual(Token{ .number = 123 }, tokens[1]);
    try std.testing.expectEqual(.end, tokens[2]);
}

test "tokenize array index" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed(".[0]");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(5, tokens.len);
    try std.testing.expectEqual(.dot, tokens[0]);
    try std.testing.expectEqual(.bracket_left, tokens[1]);
    try std.testing.expectEqual(Token{ .number = 0 }, tokens[2]);
    try std.testing.expectEqual(.bracket_right, tokens[3]);
    try std.testing.expectEqual(.end, tokens[4]);
}

test "tokenize empty input returns error" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed("");
    const result = tokenize(allocator.allocator(), &reader);

    try std.testing.expectError(error.UnexpectedEnd, result);
}

test "tokenize invalid character returns error" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed("`");
    const result = tokenize(allocator.allocator(), &reader);

    try std.testing.expectError(error.InvalidCharacter, result);
}

test "tokenize identifiers" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed("foo _foo foo2");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(4, tokens.len);
    try std.testing.expectEqualStrings("foo", tokens[0].identifier);
    try std.testing.expectEqualStrings("_foo", tokens[1].identifier);
    try std.testing.expectEqualStrings("foo2", tokens[2].identifier);
    try std.testing.expectEqual(.end, tokens[3]);
}

test "tokenize namespaced identifier" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed("foo::bar foo::bar::baz");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(3, tokens.len);
    try std.testing.expectEqualStrings("foo::bar", tokens[0].identifier);
    try std.testing.expectEqualStrings("foo::bar::baz", tokens[1].identifier);
    try std.testing.expectEqual(.end, tokens[2]);
}

test "tokenize identifier followed by colon" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed("foo:bar");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(4, tokens.len);
    try std.testing.expectEqualStrings("foo", tokens[0].identifier);
    try std.testing.expectEqual(.colon, tokens[1]);
    try std.testing.expectEqualStrings("bar", tokens[2].identifier);
    try std.testing.expectEqual(.end, tokens[3]);
}

test "tokenize identifier in complex query" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed(".foo | bar::baz");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(5, tokens.len);
    try std.testing.expectEqual(.dot, tokens[0]);
    try std.testing.expectEqualStrings("foo", tokens[1].identifier);
    try std.testing.expectEqual(.pipe, tokens[2]);
    try std.testing.expectEqualStrings("bar::baz", tokens[3].identifier);
    try std.testing.expectEqual(.end, tokens[4]);
}

test "tokenize keywords" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed(
        \\and as break catch def elif else end false foreach
        \\if import include label module null or reduce then true try
    );
    const tokens = try tokenize(allocator.allocator(), &reader);

    const expected = [_]Token{
        .keyword_and,
        .keyword_as,
        .keyword_break,
        .keyword_catch,
        .keyword_def,
        .keyword_elif,
        .keyword_else,
        .keyword_end,
        .keyword_false,
        .keyword_foreach,
        .keyword_if,
        .keyword_import,
        .keyword_include,
        .keyword_label,
        .keyword_module,
        .keyword_null,
        .keyword_or,
        .keyword_reduce,
        .keyword_then,
        .keyword_true,
        .keyword_try,
        .end,
    };
    try std.testing.expectEqual(expected.len, tokens.len);
    for (expected, tokens) |e, t| {
        try std.testing.expectEqual(e, t);
    }
}

test "tokenize keyword-like identifiers" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed("iff define for");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(4, tokens.len);
    try std.testing.expectEqualStrings("iff", tokens[0].identifier);
    try std.testing.expectEqualStrings("define", tokens[1].identifier);
    try std.testing.expectEqualStrings("for", tokens[2].identifier);
    try std.testing.expectEqual(.end, tokens[3]);
}

test "tokenize with comments" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed(
        \\.foo # this is a comment
        \\| bar
    );
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(5, tokens.len);
    try std.testing.expectEqual(.dot, tokens[0]);
    try std.testing.expectEqualStrings("foo", tokens[1].identifier);
    try std.testing.expectEqual(.pipe, tokens[2]);
    try std.testing.expectEqualStrings("bar", tokens[3].identifier);
    try std.testing.expectEqual(.end, tokens[4]);
}

test "tokenize comment at end of input" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed(".foo # comment without newline");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(3, tokens.len);
    try std.testing.expectEqual(.dot, tokens[0]);
    try std.testing.expectEqualStrings("foo", tokens[1].identifier);
    try std.testing.expectEqual(.end, tokens[2]);
}

test "tokenize comment with line continuation" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed(
        \\.foo # comment \
        \\this is also comment
        \\| bar
    );
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(5, tokens.len);
    try std.testing.expectEqual(.dot, tokens[0]);
    try std.testing.expectEqualStrings("foo", tokens[1].identifier);
    try std.testing.expectEqual(.pipe, tokens[2]);
    try std.testing.expectEqualStrings("bar", tokens[3].identifier);
    try std.testing.expectEqual(.end, tokens[4]);
}

test "tokenize comment with escaped backslash before newline" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    // Two backslashes (even) before newline: comment ends
    var reader = std.Io.Reader.fixed(
        \\.foo # comment \\
        \\| bar
    );
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(5, tokens.len);
    try std.testing.expectEqual(.dot, tokens[0]);
    try std.testing.expectEqualStrings("foo", tokens[1].identifier);
    try std.testing.expectEqual(.pipe, tokens[2]);
    try std.testing.expectEqualStrings("bar", tokens[3].identifier);
    try std.testing.expectEqual(.end, tokens[4]);
}

test "tokenize comment with three backslashes before newline" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    // Three backslashes (odd) before newline: comment continues
    var reader = std.Io.Reader.fixed(
        \\.foo # comment \\\
        \\this is also comment
        \\| bar
    );
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(5, tokens.len);
    try std.testing.expectEqual(.dot, tokens[0]);
    try std.testing.expectEqualStrings("foo", tokens[1].identifier);
    try std.testing.expectEqual(.pipe, tokens[2]);
    try std.testing.expectEqualStrings("bar", tokens[3].identifier);
    try std.testing.expectEqual(.end, tokens[4]);
}

test "tokenize comment with CRLF" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed(".foo # comment\r\n| bar");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(5, tokens.len);
    try std.testing.expectEqual(.dot, tokens[0]);
    try std.testing.expectEqualStrings("foo", tokens[1].identifier);
    try std.testing.expectEqual(.pipe, tokens[2]);
    try std.testing.expectEqualStrings("bar", tokens[3].identifier);
    try std.testing.expectEqual(.end, tokens[4]);
}

test "tokenize comment with line continuation before CRLF" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed(".foo # comment \\\r\nthis is also comment\r\n| bar");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(5, tokens.len);
    try std.testing.expectEqual(.dot, tokens[0]);
    try std.testing.expectEqualStrings("foo", tokens[1].identifier);
    try std.testing.expectEqual(.pipe, tokens[2]);
    try std.testing.expectEqualStrings("bar", tokens[3].identifier);
    try std.testing.expectEqual(.end, tokens[4]);
}

test "tokenize comment with single CR does not end comment" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed(".foo # comment\r| bar\n| baz");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(5, tokens.len);
    try std.testing.expectEqual(.dot, tokens[0]);
    try std.testing.expectEqualStrings("foo", tokens[1].identifier);
    try std.testing.expectEqual(.pipe, tokens[2]);
    try std.testing.expectEqualStrings("baz", tokens[3].identifier);
    try std.testing.expectEqual(.end, tokens[4]);
}

test "tokenize floating point numbers" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed("3.14 1.5 0.5");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(4, tokens.len);
    try std.testing.expectEqual(Token{ .number = 3.14 }, tokens[0]);
    try std.testing.expectEqual(Token{ .number = 1.5 }, tokens[1]);
    try std.testing.expectEqual(Token{ .number = 0.5 }, tokens[2]);
    try std.testing.expectEqual(.end, tokens[3]);
}

test "tokenize exponent notation" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed("1e10 1E10 1e+10 1e-10");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(5, tokens.len);
    try std.testing.expectEqual(Token{ .number = 1e10 }, tokens[0]);
    try std.testing.expectEqual(Token{ .number = 1e10 }, tokens[1]);
    try std.testing.expectEqual(Token{ .number = 1e10 }, tokens[2]);
    try std.testing.expectEqual(Token{ .number = 1e-10 }, tokens[3]);
    try std.testing.expectEqual(.end, tokens[4]);
}

test "tokenize float with exponent" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed("1.5e-3 2.5E+2");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(3, tokens.len);
    try std.testing.expectEqual(Token{ .number = 1.5e-3 }, tokens[0]);
    try std.testing.expectEqual(Token{ .number = 2.5e+2 }, tokens[1]);
    try std.testing.expectEqual(.end, tokens[2]);
}

test "tokenize number followed by dot dot" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    // "1..2" should be parsed as 1, .., 2 not 1. .2
    var reader = std.Io.Reader.fixed("1..2");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(4, tokens.len);
    try std.testing.expectEqual(Token{ .number = 1 }, tokens[0]);
    try std.testing.expectEqual(.dot_dot, tokens[1]);
    try std.testing.expectEqual(Token{ .number = 2 }, tokens[2]);
    try std.testing.expectEqual(.end, tokens[3]);
}

test "tokenize invalid exponent" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed("1e");
    const result = tokenize(allocator.allocator(), &reader);

    try std.testing.expectError(error.InvalidNumber, result);
}

test "tokenize invalid exponent with sign only" {
    var allocator = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer allocator.deinit();

    var reader = std.Io.Reader.fixed("1e+");
    const result = tokenize(allocator.allocator(), &reader);

    try std.testing.expectError(error.InvalidNumber, result);
}
