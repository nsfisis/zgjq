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
