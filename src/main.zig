const std = @import("std");
const root = @import("root.zig");

pub fn main() !void {
    var gpa = std.heap.smp_allocator;
    var threadedIO: std.Io.Threaded = .init(gpa, .{});
    defer threadedIO.deinit();
    const io = threadedIO.io();

    std.debug.print("Generating PESELs...\n", .{});
    const buffer = try root.generatePesels(gpa);
    defer gpa.free(buffer);

    var file = try std.Io.Dir.cwd().createFile(io, "pesel.txt", .{});
    defer file.close(io);

    const data = root.generatePesels(gpa) catch "ERROR";
    std.debug.print("Generated {} bytes. Writing to 'pesel.txt' file...\n", .{buffer.len});
    _ = try file.writeStreamingAll(io, data);

    std.debug.print("Done.\n", .{});
}
