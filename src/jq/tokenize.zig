const std = @import("std");

pub const TokenizeError = error{
    UnexpectedEnd,
};

pub const TokenKind = enum {
    end,
    identity,
};

pub const Token = struct {
    kind: TokenKind,
};

pub fn tokenize(allocator: std.mem.Allocator, query: []const u8) ![]Token {
    var tokens = try std.array_list.Aligned(Token, null).initCapacity(allocator, 16);

    const len = query.len;
    var i: usize = 0;
    while (i < len) {
        const c = query[i];
        if (c == '.') {
            try tokens.append(allocator, .{ .kind = .identity });
        } else {
            return TokenizeError.UnexpectedEnd;
        }
        i += 1;
    }

    try tokens.append(allocator, .{ .kind = .end });
    return tokens.toOwnedSlice(allocator);
}
