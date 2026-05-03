const std = @import("std");
const jq = @import("zgjq").jq;
const jv = @import("zgjq").jv;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

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
        try std.Io.File.stderr().writeStreamingAll(init.io, "usage: zgjq [--debug-dump-disasm] <query>\n");
        std.process.exit(1);
    }

    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(init.io, &stdin_buf);
    const input = try stdin_reader.interface.allocRemaining(allocator, std.Io.Limit.unlimited);
    defer allocator.free(input);

    const parsed = try jv.parse(allocator, input);
    defer parsed.deinit();
    const json = parsed.value;

    var runtime = try jq.Runtime.init(allocator);
    defer runtime.deinit();
    try runtime.compileFromSlice(query.?);

    if (debug_dump_disasm) {
        var stderr_buf: [4096]u8 = undefined;
        var stderr = std.Io.File.stderr().writer(init.io, &stderr_buf);
        try runtime.dumpDisasm(&stderr.interface);
        try stderr.interface.flush();
    }

    try runtime.start(json);

    const stdout = std.Io.File.stdout();
    while (try runtime.next()) |result| {
        const output = try jv.stringify(allocator, result);
        defer allocator.free(output);
        try stdout.writeStreamingAll(init.io, output);
        try stdout.writeStreamingAll(init.io, "\n");
    }
}
