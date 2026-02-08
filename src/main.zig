const std = @import("std");
const jq = @import("zgjq").jq;
const jv = @import("zgjq").jv;

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var debug_dump_disasm = false;
    var query: ?[]const u8 = null;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--debug-dump-disasm")) {
            debug_dump_disasm = true;
        } else if (query == null) {
            query = arg;
        }
    }

    if (query == null) {
        try std.fs.File.stderr().writeAll("usage: zgjq [--debug-dump-disasm] <query>\n");
        std.process.exit(1);
    }

    const input = try std.fs.File.stdin().readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(input);

    const parsed = try jv.parse(allocator, input);
    defer parsed.deinit();
    const json = parsed.value;

    var runtime = try jq.Runtime.init(allocator);
    defer runtime.deinit();
    try runtime.compileFromSlice(query.?);

    if (debug_dump_disasm) {
        var buf: [4096]u8 = undefined;
        var stderr = std.fs.File.stderr().writer(&buf);
        try runtime.dumpDisasm(&stderr.interface);
        try stderr.interface.flush();
    }

    try runtime.start(json);

    const stdout = std.fs.File.stdout();
    while (try runtime.next()) |result| {
        const output = try jv.stringify(allocator, result);
        defer allocator.free(output);
        try stdout.writeAll(output);
        try stdout.writeAll("\n");
    }
}
