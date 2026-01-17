const std = @import("std");

pub const TokenizeError = error{
    UnexpectedEnd,
    InvalidCharacter,
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

    number: i64,

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

pub fn tokenize(allocator: std.mem.Allocator, reader: *std.Io.Reader) ![]Token {
    var tokens = try std.array_list.Aligned(Token, null).initCapacity(allocator, 16);

    while (true) {
        const c = reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            error.ReadFailed => return error.ReadFailed,
        };
        switch (c) {
            ' ', '\t', '\n', '\r' => continue,
            '$' => try tokens.append(allocator, .dollar),
            '%' => try tokens.append(allocator, if (try peekByte(reader) == '=') blk: {
                _ = reader.takeByte() catch unreachable;
                break :blk .percent_equal;
            } else .percent),
            '(' => try tokens.append(allocator, .paren_left),
            ')' => try tokens.append(allocator, .paren_right),
            '*' => try tokens.append(allocator, if (try peekByte(reader) == '=') blk: {
                _ = reader.takeByte() catch unreachable;
                break :blk .asterisk_equal;
            } else .asterisk),
            '+' => try tokens.append(allocator, if (try peekByte(reader) == '=') blk: {
                _ = reader.takeByte() catch unreachable;
                break :blk .plus_equal;
            } else .plus),
            ',' => try tokens.append(allocator, .comma),
            '-' => try tokens.append(allocator, if (try peekByte(reader) == '=') blk: {
                _ = reader.takeByte() catch unreachable;
                break :blk .minus_equal;
            } else .minus),
            '.' => try tokens.append(allocator, if (try peekByte(reader) == '.') blk: {
                _ = reader.takeByte() catch unreachable;
                break :blk .dot_dot;
            } else .dot),
            '/' => {
                if (try peekByte(reader) == '/') {
                    _ = reader.takeByte() catch unreachable;
                    try tokens.append(allocator, if (try peekByte(reader) == '=') blk: {
                        _ = reader.takeByte() catch unreachable;
                        break :blk .slash_slash_equal;
                    } else .slash_slash);
                } else if (try peekByte(reader) == '=') {
                    _ = reader.takeByte() catch unreachable;
                    try tokens.append(allocator, .slash_equal);
                } else {
                    try tokens.append(allocator, .slash);
                }
            },
            ':' => try tokens.append(allocator, .colon),
            ';' => try tokens.append(allocator, .semicolon),
            '<' => try tokens.append(allocator, if (try peekByte(reader) == '=') blk: {
                _ = reader.takeByte() catch unreachable;
                break :blk .less_than_equal;
            } else .less_than),
            '=' => try tokens.append(allocator, if (try peekByte(reader) == '=') blk: {
                _ = reader.takeByte() catch unreachable;
                break :blk .equal_equal;
            } else .equal),
            '>' => try tokens.append(allocator, if (try peekByte(reader) == '=') blk: {
                _ = reader.takeByte() catch unreachable;
                break :blk .greater_than_equal;
            } else .greater_than),
            '!' => {
                if (try peekByte(reader) == '=') {
                    _ = reader.takeByte() catch unreachable;
                    try tokens.append(allocator, .not_equal);
                } else {
                    return error.InvalidCharacter;
                }
            },
            '?' => {
                if (try peekByte(reader) == '/') {
                    _ = reader.takeByte() catch unreachable;
                    if (try peekByte(reader) == '/') {
                        _ = reader.takeByte() catch unreachable;
                        try tokens.append(allocator, .question_slash_slash);
                    } else {
                        return error.InvalidCharacter;
                    }
                } else {
                    try tokens.append(allocator, .question);
                }
            },
            '[' => try tokens.append(allocator, .bracket_left),
            ']' => try tokens.append(allocator, .bracket_right),
            '{' => try tokens.append(allocator, .brace_left),
            '|' => try tokens.append(allocator, if (try peekByte(reader) == '=') blk: {
                _ = reader.takeByte() catch unreachable;
                break :blk .pipe_equal;
            } else .pipe),
            '}' => try tokens.append(allocator, .brace_right),
            else => {
                if (std.ascii.isDigit(c)) {
                    try tokens.append(allocator, .{ .number = (c - '0') });
                } else {
                    return error.InvalidCharacter;
                }
            },
        }
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

    var reader = std.Io.Reader.fixed("5");
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(2, tokens.len);
    try std.testing.expectEqual(Token{ .number = 5 }, tokens[0]);
    try std.testing.expectEqual(.end, tokens[1]);
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
