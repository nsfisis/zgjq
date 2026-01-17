const std = @import("std");
const jv = @import("../jv.zig");
const Instr = @import("./compile.zig").Instr;

pub const ExecuteError = error{
    Unimplemented,
    InvalidType,
    InternalError,
};

pub fn execute(allocator: std.mem.Allocator, instrs: []const Instr, input: jv.Value) !jv.Value {
    var value_stack = try std.array_list.Aligned(jv.Value, null).initCapacity(allocator, 16);
    defer value_stack.deinit(allocator);

    try value_stack.append(allocator, input);

    const len = instrs.len;
    var pc: usize = 0;
    while (pc < len) {
        const cur = instrs[pc];
        switch (cur) {
            .nop => {},
            .array_index => {
                const v1 = value_stack.pop() orelse return error.InternalError;
                const v1_integer = switch (v1) {
                    .integer => |integer| integer,
                    else => return error.InvalidType,
                };
                const v2 = value_stack.pop() orelse return error.InternalError;
                const v2_array = switch (v2) {
                    .array => |array| array,
                    else => return error.InvalidType,
                };
                const index: usize = @intCast(v1_integer);
                const result = if (index < v2_array.items.len) v2_array.items[index] else .null;
                try value_stack.append(allocator, result);
            },
            .literal => |value| {
                try value_stack.append(allocator, value.*);
            },
        }
        pc += 1;
    }

    const result = value_stack.pop() orelse return error.InternalError;
    return result;
}
