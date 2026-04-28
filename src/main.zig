const std = @import("std");
const root = @import("root.zig");

pub fn main() !void {
    var gpa = std.heap.smp_allocator;
    var thrededIO: std.Io.Threaded = .init(gpa, .{});
    defer thrededIO.deinit();
    const io = thrededIO.io();

    std.debug.print("Generating PESELs...\n", .{});
    const buffer = try root.generatePesels(gpa);
    defer gpa.free(buffer);

    const path = std.Io.Dir.cwd().openDir(io, .{}, .{});

    std.debug.print("Generated {} bytes. Writing to 'pesel' file...\n", .{buffer.len});

    std.debug.print("Done.\n", .{});
}
