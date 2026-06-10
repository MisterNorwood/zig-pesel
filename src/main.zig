const std = @import("std");
const root = @import("root.zig");

const tree_file_limit = 64 * 1024 * 1024;

const KeyImportSummary = struct {
    inserted: usize = 0,
    duplicates: usize = 0,
    blank_lines: usize = 0,
};

const TreeSession = union(enum) {
    avl: root.AvlTree,
    red_black: root.RedBlackTree,
    two_three_four: root.TwoThreeFourTree,

    fn init(tree_kind: root.TreeKind, allocator: std.mem.Allocator) TreeSession {
        return switch (tree_kind) {
            .avl => .{ .avl = root.AvlTree.init(allocator) },
            .red_black => .{ .red_black = root.RedBlackTree.init(allocator) },
            .two_three_four => .{ .two_three_four = root.TwoThreeFourTree.init(allocator) },
        };
    }

    fn deinit(self: *TreeSession) void {
        switch (self.*) {
            .avl => |*tree| tree.deinit(),
            .red_black => |*tree| tree.deinit(),
            .two_three_four => |*tree| tree.deinit(),
        }
    }

    fn kind(self: *const TreeSession) root.TreeKind {
        return switch (self.*) {
            .avl => .avl,
            .red_black => .red_black,
            .two_three_four => .two_three_four,
        };
    }

    fn kindName(self: *const TreeSession) []const u8 {
        return kindNameFromKind(self.kind());
    }

    fn len(self: *const TreeSession) usize {
        return switch (self.*) {
            .avl => |tree| tree.len,
            .red_black => |tree| tree.len,
            .two_three_four => |tree| tree.len,
        };
    }

    fn insert(self: *TreeSession, key: u64) !bool {
        return switch (self.*) {
            .avl => |*tree| tree.insert(key),
            .red_black => |*tree| tree.insert(key),
            .two_three_four => |*tree| tree.insert(key),
        };
    }

    fn remove(self: *TreeSession, key: u64) !bool {
        return switch (self.*) {
            .avl => |*tree| tree.remove(key),
            .red_black => |*tree| tree.remove(key),
            .two_three_four => |*tree| tree.remove(key),
        };
    }

    fn contains(self: *const TreeSession, key: u64) bool {
        return switch (self.*) {
            .avl => |tree| tree.contains(key),
            .red_black => |tree| tree.contains(key),
            .two_three_four => |tree| tree.contains(key),
        };
    }

    fn serialize(self: *const TreeSession, allocator: std.mem.Allocator) ![]u8 {
        return switch (self.*) {
            .avl => |tree| tree.serialize(allocator),
            .red_black => |tree| tree.serialize(allocator),
            .two_three_four => |tree| tree.serialize(allocator),
        };
    }

    fn writeIndented(self: *const TreeSession, writer: *std.Io.Writer) !void {
        switch (self.*) {
            .avl => |tree| try tree.writeIndented(writer),
            .red_black => |tree| try tree.writeIndented(writer),
            .two_three_four => |tree| try tree.writeIndented(writer),
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var stdin_buffer: [4096]u8 = undefined;
    var stdout_buffer: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buffer);
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const input = &stdin_reader.interface;
    const output = &stdout_writer.interface;
    defer output.flush() catch {};

    if (args.len > 1) {
        try handleArgs(gpa, io, input, output, args[1..]);
        try output.flush();
        return;
    }

    try runInteractive(gpa, io, input, output);
    try output.flush();
}

fn handleArgs(
    allocator: std.mem.Allocator,
    io: std.Io,
    input: *std.Io.Reader,
    output: *std.Io.Writer,
    args: []const [:0]const u8,
) !void {
    if (std.mem.eql(u8, args[0], "generate")) {
        if (args.len != 3) {
            try output.writeAll("Usage: zig_pesel generate <count> <file>\n");
            return;
        }
        const count = try parseUsize(args[1]);
        try generatePeselFile(allocator, io, output, count, args[2]);
        return;
    }

    if (std.mem.eql(u8, args[0], "tree")) {
        if (args.len > 1) {
            const tail = try std.mem.join(allocator, " ", args[1..]);
            defer allocator.free(tail);
            try handleTreeCommand(allocator, io, input, output, tail);
        } else {
            try handleTreeCommand(allocator, io, input, output, "");
        }
        return;
    }

    try output.writeAll("Unknown command. Supported commands: generate, tree\n");
}

fn runInteractive(
    allocator: std.mem.Allocator,
    io: std.Io,
    input: *std.Io.Reader,
    output: *std.Io.Writer,
) !void {
    try writeMainHelp(output);

    while (true) {
        try output.writeAll("main> ");
        try output.flush();

        const line = (try readLine(input)) orelse return;
        if (line.len == 0) continue;

        const split = splitFirstToken(line);
        if (std.mem.eql(u8, split.head, "help")) {
            try writeMainHelp(output);
            continue;
        }
        if (std.mem.eql(u8, split.head, "quit") or std.mem.eql(u8, split.head, "exit")) {
            return;
        }
        if (std.mem.eql(u8, split.head, "generate")) {
            try handleGenerateCommand(allocator, io, input, output, split.tail);
            continue;
        }
        if (std.mem.eql(u8, split.head, "tree")) {
            try handleTreeCommand(allocator, io, input, output, split.tail);
            continue;
        }

        try output.writeAll("Unknown command. Type 'help' for available commands.\n");
    }
}

fn handleGenerateCommand(
    allocator: std.mem.Allocator,
    io: std.Io,
    input: *std.Io.Reader,
    output: *std.Io.Writer,
    tail: []const u8,
) !void {
    var count: usize = undefined;
    var path_buf: [1024]u8 = undefined;
    var path: []const u8 = undefined;

    if (tail.len == 0) {
        try output.print("PESEL count [{}]: ", .{root.default_pesel_count});
        try output.flush();
        const count_line = (try readLine(input)) orelse return;
        count = if (count_line.len == 0) root.default_pesel_count else try parseUsize(count_line);

        try output.print("Output file [{s}]: ", .{root.default_pesel_path});
        try output.flush();
        const path_line = (try readLine(input)) orelse return;
        const chosen = if (path_line.len == 0) root.default_pesel_path else path_line;
        @memcpy(path_buf[0..chosen.len], chosen);
        path = path_buf[0..chosen.len];
    } else {
        const first = splitFirstToken(tail);
        if (first.tail.len == 0) {
            try output.writeAll("Usage: generate <count> <file>\n");
            return;
        }
        count = try parseUsize(first.head);
        @memcpy(path_buf[0..first.tail.len], first.tail);
        path = path_buf[0..first.tail.len];
    }

    try generatePeselFile(allocator, io, output, count, path);
}

fn generatePeselFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    output: *std.Io.Writer,
    count: usize,
    path: []const u8,
) !void {
    const created = try root.ensureRandomPeselFile(std.Io.Dir.cwd(), io, allocator, path, count);
    if (created) {
        try output.print("Generated {} PESELs into '{s}'.\n", .{ count, path });
    } else {
        try output.print("'{s}' already exists. Generation skipped.\n", .{path});
    }
}

fn handleTreeCommand(
    allocator: std.mem.Allocator,
    io: std.Io,
    input: *std.Io.Reader,
    output: *std.Io.Writer,
    tail: []const u8,
) !void {
    if (tail.len == 0) {
        try output.writeAll(
            \\Tree commands:
            \\  tree new <avl|rb|234> [keys-file]
            \\  tree load <file>
            \\If no arguments are given, you will be prompted interactively.
            \\
        );
        try output.writeAll("Create new tree or load existing one? [new/load]: ");
        try output.flush();
        const mode_line = (try readLine(input)) orelse return;
        if (std.mem.eql(u8, mode_line, "new")) {
            try output.writeAll("Tree type [avl/rb/234]: ");
            try output.flush();
            const type_line = (try readLine(input)) orelse return;
            const kind = parseTreeKind(type_line) orelse {
                try output.writeAll("Unknown tree type.\n");
                return;
            };
            var session = TreeSession.init(kind, allocator);
            defer session.deinit();
            try output.writeAll("Key file to import [empty to skip]: ");
            try output.flush();
            const path_line = (try readLine(input)) orelse return;
            if (path_line.len != 0) {
                const imported = try importKeysIntoSessionOrReport(&session, allocator, io, output, path_line);
                if (!imported) return;
            }
            try runTreeSession(&session, allocator, io, input, output);
            return;
        }
        if (std.mem.eql(u8, mode_line, "load")) {
            try output.writeAll("File path: ");
            try output.flush();
            const path_line = (try readLine(input)) orelse return;
            var session = try loadTreeSession(allocator, io, path_line);
            defer session.deinit();
            try runTreeSession(&session, allocator, io, input, output);
            return;
        }
        try output.writeAll("Unknown mode.\n");
        return;
    }

    const command = splitFirstToken(tail);
    if (std.mem.eql(u8, command.head, "new")) {
        const new_args = splitFirstToken(command.tail);
        if (new_args.head.len == 0) {
            try output.writeAll("Usage: tree new <avl|rb|234> [keys-file]\n");
            return;
        }
        const kind = parseTreeKind(new_args.head) orelse {
            try output.writeAll("Unknown tree type.\n");
            return;
        };
        var session = TreeSession.init(kind, allocator);
        defer session.deinit();
        if (new_args.tail.len != 0) {
            const imported = try importKeysIntoSessionOrReport(&session, allocator, io, output, new_args.tail);
            if (!imported) return;
        }
        try runTreeSession(&session, allocator, io, input, output);
        return;
    }

    if (std.mem.eql(u8, command.head, "load")) {
        if (command.tail.len == 0) {
            try output.writeAll("Usage: tree load <file>\n");
            return;
        }
        var session = try loadTreeSession(allocator, io, command.tail);
        defer session.deinit();
        try runTreeSession(&session, allocator, io, input, output);
        return;
    }

    try output.writeAll("Usage: tree new <avl|rb|234> | tree load <file>\n");
}

fn runTreeSession(
    session: *TreeSession,
    allocator: std.mem.Allocator,
    io: std.Io,
    input: *std.Io.Reader,
    output: *std.Io.Writer,
) !void {
    try output.print("Tree session started for {s}.\n", .{session.kindName()});
    try writeTreeHelp(output);

    while (true) {
        try output.print("tree[{s}]> ", .{session.kindName()});
        try output.flush();

        const line = (try readLine(input)) orelse return;
        if (line.len == 0) continue;

        const split = splitFirstToken(line);
        if (std.mem.eql(u8, split.head, "help")) {
            try writeTreeHelp(output);
            continue;
        }
        if (std.mem.eql(u8, split.head, "back")) {
            return;
        }
        if (std.mem.eql(u8, split.head, "quit") or std.mem.eql(u8, split.head, "exit")) {
            std.process.exit(0);
        }
        if (std.mem.eql(u8, split.head, "insert")) {
            const key = (try parseRequiredU64(output, split.tail, "Usage: insert <key>\n")) orelse continue;
            if (try session.insert(key)) {
                try output.print("Inserted {}.\n", .{key});
            } else {
                try output.print("Key {} already exists.\n", .{key});
            }
            continue;
        }
        if (std.mem.eql(u8, split.head, "remove")) {
            const key = (try parseRequiredU64(output, split.tail, "Usage: remove <key>\n")) orelse continue;
            if (try session.remove(key)) {
                try output.print("Removed {}.\n", .{key});
            } else {
                try output.print("Key {} not found.\n", .{key});
            }
            continue;
        }
        if (std.mem.eql(u8, split.head, "contains")) {
            const key = (try parseRequiredU64(output, split.tail, "Usage: contains <key>\n")) orelse continue;
            try output.print("{}\n", .{session.contains(key)});
            continue;
        }
        if (std.mem.eql(u8, split.head, "stats")) {
            try output.print("type={s} nodes={}\n", .{ session.kindName(), session.len() });
            continue;
        }
        if (std.mem.eql(u8, split.head, "import")) {
            if (split.tail.len == 0) {
                try output.writeAll("Usage: import <file>\n");
                continue;
            }
            const imported = try importKeysIntoSessionOrReport(session, allocator, io, output, split.tail);
            if (imported) {
                try output.print("Tree now contains {} keys.\n", .{session.len()});
            }
            continue;
        }
        if (std.mem.eql(u8, split.head, "print") or std.mem.eql(u8, split.head, "explore")) {
            try session.writeIndented(output);
            continue;
        }
        if (std.mem.eql(u8, split.head, "save")) {
            if (split.tail.len == 0) {
                try output.writeAll("Usage: save <file>\n");
                continue;
            }
            try saveTreeSession(session, allocator, io, split.tail);
            try output.print("Saved {s} tree to '{s}'.\n", .{ session.kindName(), split.tail });
            continue;
        }
        if (std.mem.eql(u8, split.head, "load")) {
            if (split.tail.len == 0) {
                try output.writeAll("Usage: load <file>\n");
                continue;
            }
            const loaded = try loadTreeSession(allocator, io, split.tail);
            session.deinit();
            session.* = loaded;
            try output.print("Loaded {s} tree from '{s}'.\n", .{ session.kindName(), split.tail });
            continue;
        }

        try output.writeAll("Unknown tree command. Type 'help' for available commands.\n");
    }
}

fn saveTreeSession(session: *const TreeSession, allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    const data = try session.serialize(allocator);
    defer allocator.free(data);

    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    try file.writeStreamingAll(io, data);
}

fn loadTreeSession(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !TreeSession {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(tree_file_limit));
    defer allocator.free(data);

    return switch (try root.serializedTreeKind(data)) {
        .avl => .{ .avl = try root.AvlTree.deserialize(allocator, data) },
        .red_black => .{ .red_black = try root.RedBlackTree.deserialize(allocator, data) },
        .two_three_four => .{ .two_three_four = try root.TwoThreeFourTree.deserialize(allocator, data) },
    };
}

fn importKeysIntoSessionOrReport(
    session: *TreeSession,
    allocator: std.mem.Allocator,
    io: std.Io,
    output: *std.Io.Writer,
    path: []const u8,
) !bool {
    var invalid_line: ?usize = null;
    const summary = importKeysFromFile(session, allocator, io, path, &invalid_line) catch |err| switch (err) {
        error.InvalidKeyLine => {
            if (invalid_line) |line_no| {
                try output.print(
                    "Invalid key at line {} in '{s}'. Expected one unsigned integer per line.\n",
                    .{ line_no, path },
                );
            } else {
                try output.print("Invalid key file '{s}'.\n", .{path});
            }
            return false;
        },
        else => return err,
    };

    try output.print(
        "Imported {} keys from '{s}' (duplicates skipped: {}, blank lines ignored: {}).\n",
        .{ summary.inserted, path, summary.duplicates, summary.blank_lines },
    );
    return true;
}

fn importKeysFromFile(
    session: *TreeSession,
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    invalid_line: *?usize,
) !KeyImportSummary {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(tree_file_limit));
    defer allocator.free(data);

    return importKeysFromText(session, allocator, data, invalid_line);
}

fn importKeysFromText(
    session: *TreeSession,
    allocator: std.mem.Allocator,
    data: []const u8,
    invalid_line: *?usize,
) !KeyImportSummary {
    var keys: std.ArrayList(u64) = .empty;
    defer keys.deinit(allocator);

    invalid_line.* = null;
    var summary: KeyImportSummary = .{};
    var line_no: usize = 0;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw_line| {
        line_no += 1;
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) {
            summary.blank_lines += 1;
            continue;
        }

        const key = parseU64(line) catch {
            invalid_line.* = line_no;
            return error.InvalidKeyLine;
        };
        try keys.append(allocator, key);
    }

    for (keys.items) |key| {
        if (try session.insert(key)) {
            summary.inserted += 1;
        } else {
            summary.duplicates += 1;
        }
    }
    return summary;
}

fn writeMainHelp(output: *std.Io.Writer) !void {
    try output.writeAll(
        \\Commands:
        \\  help
        \\  generate [count file]
        \\  tree [new <avl|rb|234> [keys-file] | load <file>]
        \\  quit
        \\
    );
}

fn writeTreeHelp(output: *std.Io.Writer) !void {
    try output.writeAll(
        \\Tree session commands:
        \\  help
        \\  insert <key>
        \\  remove <key>
        \\  contains <key>
        \\  import <file>
        \\  print
        \\  explore
        \\  stats
        \\  save <file>
        \\  load <file>
        \\  back
        \\  quit
        \\
    );
}

fn readLine(input: *std.Io.Reader) !?[]const u8 {
    const line = (try input.takeDelimiter('\n')) orelse return null;
    return std.mem.trim(u8, line, "\r");
}

fn splitFirstToken(line: []const u8) struct { head: []const u8, tail: []const u8 } {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0) return .{ .head = "", .tail = "" };

    const split_at = std.mem.indexOfAny(u8, trimmed, " \t") orelse {
        return .{ .head = trimmed, .tail = "" };
    };

    return .{
        .head = trimmed[0..split_at],
        .tail = std.mem.trim(u8, trimmed[split_at + 1 ..], " \t"),
    };
}

fn parseTreeKind(raw: []const u8) ?root.TreeKind {
    const value = std.mem.trim(u8, raw, " \t");
    if (std.mem.eql(u8, value, "avl")) return .avl;
    if (std.mem.eql(u8, value, "rb")) return .red_black;
    if (std.mem.eql(u8, value, "red-black")) return .red_black;
    if (std.mem.eql(u8, value, "redblack")) return .red_black;
    if (std.mem.eql(u8, value, "234")) return .two_three_four;
    if (std.mem.eql(u8, value, "2-3-4")) return .two_three_four;
    return null;
}

fn kindNameFromKind(kind: root.TreeKind) []const u8 {
    return switch (kind) {
        .avl => "avl",
        .red_black => "red-black",
        .two_three_four => "2-3-4",
    };
}

fn parseUsize(raw: []const u8) !usize {
    return std.fmt.parseUnsigned(usize, std.mem.trim(u8, raw, " \t"), 10);
}

fn parseU64(raw: []const u8) !u64 {
    return std.fmt.parseUnsigned(u64, std.mem.trim(u8, raw, " \t"), 10);
}

fn parseRequiredU64(output: *std.Io.Writer, raw: []const u8, usage: []const u8) !?u64 {
    if (raw.len == 0) {
        try output.writeAll(usage);
        return null;
    }
    return try parseU64(raw);
}

test "importKeysFromText imports LF and CRLF separated keys" {
    var session = TreeSession.init(.avl, std.testing.allocator);
    defer session.deinit();

    var invalid_line: ?usize = null;
    const summary = try importKeysFromText(&session, std.testing.allocator, "10\r\n20\n20\n\n30\r\n", &invalid_line);

    try std.testing.expectEqual(@as(?usize, null), invalid_line);
    try std.testing.expectEqual(@as(usize, 3), summary.inserted);
    try std.testing.expectEqual(@as(usize, 1), summary.duplicates);
    try std.testing.expectEqual(@as(usize, 2), summary.blank_lines);
    try std.testing.expect(session.contains(10));
    try std.testing.expect(session.contains(20));
    try std.testing.expect(session.contains(30));
    try std.testing.expectEqual(@as(usize, 3), session.len());
}

test "importKeysFromText rejects invalid lines without mutating the tree" {
    var session = TreeSession.init(.red_black, std.testing.allocator);
    defer session.deinit();

    try std.testing.expect(try session.insert(7));

    var invalid_line: ?usize = null;
    try std.testing.expectError(
        error.InvalidKeyLine,
        importKeysFromText(&session, std.testing.allocator, "10\nabc\n30\n", &invalid_line),
    );

    try std.testing.expectEqual(@as(?usize, 2), invalid_line);
    try std.testing.expectEqual(@as(usize, 1), session.len());
    try std.testing.expect(session.contains(7));
    try std.testing.expect(!session.contains(10));
    try std.testing.expect(!session.contains(30));
}
