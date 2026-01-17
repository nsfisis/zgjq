const std = @import("std");
const jv = @import("../jv.zig");
const Instr = @import("./compile.zig").Instr;

pub const ExecuteError = error{
    Unimplemented,
};

pub fn execute(allocator: std.mem.Allocator, instrs: []const Instr, input: jv.Value) !jv.Value {
    _ = allocator;
    const len = instrs.len;
    var pc: usize = 0;
    while (pc < len) {
        const cur = instrs[pc];
        _ = switch (cur.op) {
            .nop => void,
            .identity => return input,
        };
        pc += 1;
    }
    return ExecuteError.Unimplemented;
}
