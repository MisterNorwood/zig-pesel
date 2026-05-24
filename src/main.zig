const std = @import("std");
const root = @import("root.zig");

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    var threadedIO: std.Io.Threaded = .init(gpa, .{});
    defer threadedIO.deinit();
    const io = threadedIO.io();

    const generated = try root.ensureRandomPeselFile(
        std.Io.Dir.cwd(),
        io,
        gpa,
        root.default_pesel_path,
        root.default_pesel_count,
    );

    if (generated) {
        std.debug.print(
            "Generated {} random PESELs and wrote them to '{s}'.\n",
            .{ root.default_pesel_count, root.default_pesel_path },
        );
    } else {
        std.debug.print("'{s}' already exists. Skipping generation.\n", .{root.default_pesel_path});
    }
}
