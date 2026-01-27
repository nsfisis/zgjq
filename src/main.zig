const std = @import("std");
const jq = @import("zgjq").jq;
const jv = @import("zgjq").jv;

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try std.fs.File.stderr().writeAll("usage: zgjq <query>\n");
        std.process.exit(1);
    }
    const query = args[1];

    const input = try std.fs.File.stdin().readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(input);

    const parsed = try jv.parse(allocator, input);
    defer parsed.deinit();
    const json = parsed.value;

    var runtime = try jq.Runtime.init(allocator);
    defer runtime.deinit();
    try runtime.compileFromSlice(query);
    try runtime.start(json);

    const stdout = std.fs.File.stdout();
    while (try runtime.next()) |result| {
        const output = try jv.stringify(allocator, result);
        defer allocator.free(output);
        try stdout.writeAll(output);
        try stdout.writeAll("\n");
    }
}
