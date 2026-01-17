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

pub fn tokenize(allocator: std.mem.Allocator, query: []const u8) ![]Token {
    var tokens = try std.array_list.Aligned(Token, null).initCapacity(allocator, 16);

    const len = query.len;

    if (len == 0) {
        return error.UnexpectedEnd;
    }

    var i: usize = 0;
    while (i < len) {
        const c = query[i];
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
        i += 1;
    }

    try tokens.append(allocator, .end);
    return tokens.toOwnedSlice(allocator);
}
