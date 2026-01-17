const std = @import("std");

pub const TokenizeError = error{
    UnexpectedEnd,
    InvalidCharacter,
};

pub const TokenKind = enum {
    end,
    dot,
    bracket_left,
    bracket_right,
    number,
};

pub const Token = union(TokenKind) {
    end,
    dot,
    bracket_left,
    bracket_right,
    number: i64,

    pub fn kind(self: @This()) TokenKind {
        return self;
    }
};

pub fn tokenize(allocator: std.mem.Allocator, reader: *std.Io.Reader) ![]Token {
    var tokens = try std.array_list.Aligned(Token, null).initCapacity(allocator, 16);

    while (true) {
        const c = reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            error.ReadFailed => return error.ReadFailed,
        };
        switch (c) {
            '.' => try tokens.append(allocator, .dot),
            '[' => try tokens.append(allocator, .bracket_left),
            ']' => try tokens.append(allocator, .bracket_right),
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
        \\.[]
    );
    const tokens = try tokenize(allocator.allocator(), &reader);

    try std.testing.expectEqual(4, tokens.len);
    try std.testing.expectEqual(.dot, tokens[0]);
    try std.testing.expectEqual(.bracket_left, tokens[1]);
    try std.testing.expectEqual(.bracket_right, tokens[2]);
    try std.testing.expectEqual(.end, tokens[3]);
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
