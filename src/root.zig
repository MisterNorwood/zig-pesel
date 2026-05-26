const std = @import("std");

pub const default_pesel_path = "pesel.txt";
pub const default_pesel_count: usize = 400_000_000;

const line_len = 12;
const simd_lanes = 16;
const Vec = @Vector(simd_lanes, u32);
const ByteVerifyWidth = 64;
const ByteVec = @Vector(ByteVerifyWidth, u8);
const checksum_weights = [_]u32{ 1, 3, 7, 9, 1, 3, 7, 9, 1, 3 };
const min_birth_year: u32 = 1800;
const max_birth_year_exclusive: u32 = 2300;
const bucket_bits_max = std.math.Log2Int(usize);

const total_birth_days: u32 = blk: {
    @setEvalBranchQuota(10_000);
    var total: u32 = 0;
    var year = min_birth_year;
    while (year < max_birth_year_exclusive) : (year += 1) {
        total += daysInYear(year);
    }
    break :blk total;
};

const TreeCodecError = error{
    InvalidFormat,
    UnexpectedEof,
};

pub const TreeKind = enum {
    avl,
    red_black,
    two_three_four,
};

pub fn serializedTreeKind(bytes: []const u8) TreeCodecError!TreeKind {
    if (bytes.len < 4) return TreeCodecError.UnexpectedEof;
    if (std.mem.eql(u8, bytes[0..4], "AVL1")) return .avl;
    if (std.mem.eql(u8, bytes[0..4], "RBT1")) return .red_black;
    if (std.mem.eql(u8, bytes[0..4], "2341")) return .two_three_four;
    return TreeCodecError.InvalidFormat;
}

fn isLeapYear(year: u32) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

fn daysInYear(year: u32) u32 {
    return if (isLeapYear(year)) 366 else 365;
}

fn daysInMonth(year: u32, month: u32) u32 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => unreachable,
    };
}

fn daysToDate(days_since_1800: u32) [3]u32 {
    var days = days_since_1800;
    var year = min_birth_year;

    while (true) {
        const year_days = daysInYear(year);
        if (days < year_days) break;
        days -= year_days;
        year += 1;
    }

    var month: u32 = 1;
    while (true) : (month += 1) {
        const month_days = daysInMonth(year, month);
        if (days < month_days) break;
        days -= month_days;
    }

    return .{ year, month, days + 1 };
}

fn encodePeselMonth(year: u32, month: u32) u32 {
    const century_offset: u32 = switch (year / 100) {
        18 => 80,
        19 => 0,
        20 => 20,
        21 => 40,
        22 => 60,
        else => unreachable,
    };
    return month + century_offset;
}

fn decodePeselMonth(encoded_month: u32, yy: u32) ?[2]u32 {
    const century_base: u32, const month: u32 = switch (encoded_month) {
        1...12 => .{ 1900, encoded_month },
        21...32 => .{ 2000, encoded_month - 20 },
        41...52 => .{ 2100, encoded_month - 40 },
        61...72 => .{ 2200, encoded_month - 60 },
        81...92 => .{ 1800, encoded_month - 80 },
        else => return null,
    };
    return .{ century_base + yy, month };
}

fn checksumDigit(digits: *const [10]u8) u8 {
    var sum: u32 = 0;
    for (digits, 0..) |digit, index| {
        sum += @as(u32, digit) * checksum_weights[index];
    }
    return @intCast((10 - (sum % 10)) % 10);
}

fn mixSeed(seed: u64, salt: u64) u64 {
    var z = seed +% 0x9e37_79b9_7f4a_7c15 +% salt;
    z = (z ^ (z >> 30)) *% 0xbf58_476d_1ce4_e5b9;
    z = (z ^ (z >> 27)) *% 0x94d0_49bb_1331_11eb;
    return z ^ (z >> 31);
}

fn processRandomChunk(buffer_slice: []u8, seed: u64) void {
    const count = buffer_slice.len / line_len;
    if (count == 0) return;

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    var v_weights: [10]Vec = undefined;
    inline for (0..10) |i| {
        v_weights[i] = @splat(checksum_weights[i]);
    }

    const v0: Vec = @splat(0);
    const v10: Vec = @splat(10);

    var i: usize = 0;
    while (i < count) : (i += simd_lanes) {
        const lanes_this_round = @min(simd_lanes, count - i);

        var digits: [10]Vec = undefined;
        inline for (0..10) |d| digits[d] = v0;

        inline for (0..simd_lanes) |lane| {
            if (lane < lanes_this_round) {
                const birth_days = random.intRangeLessThan(u32, 0, total_birth_days);
                const serial = random.intRangeLessThan(u16, 0, 10_000);
                const date = daysToDate(birth_days);

                const year = date[0];
                const month = encodePeselMonth(year, date[1]);
                const day = date[2];

                digits[0][lane] = (year % 100) / 10;
                digits[1][lane] = (year % 100) % 10;
                digits[2][lane] = month / 10;
                digits[3][lane] = month % 10;
                digits[4][lane] = day / 10;
                digits[5][lane] = day % 10;
                digits[6][lane] = serial / 1000;
                digits[7][lane] = (serial / 100) % 10;
                digits[8][lane] = (serial / 10) % 10;
                digits[9][lane] = serial % 10;
            }
        }

        var sum: Vec = v0;
        inline for (0..10) |d| {
            sum += digits[d] * v_weights[d];
        }
        const checksum = (v10 - (sum % v10)) % v10;

        inline for (0..simd_lanes) |lane| {
            if (lane < lanes_this_round) {
                const offset = (i + lane) * line_len;
                inline for (0..10) |d| {
                    buffer_slice[offset + d] = @as(u8, @intCast(digits[d][lane])) + '0';
                }
                buffer_slice[offset + 10] = @as(u8, @intCast(checksum[lane])) + '0';
                buffer_slice[offset + 11] = '\n';
            }
        }
    }
}

fn fillRandomPeselBufferParallel(allocator: std.mem.Allocator, buffer: []u8, seed: u64) !void {
    std.debug.assert(buffer.len % line_len == 0);

    const total_count = buffer.len / line_len;
    if (total_count == 0) return;

    const min_lines_per_worker = simd_lanes * 2048;
    const cpu_count = try std.Thread.getCpuCount();
    const suggested_workers = @max(@as(usize, 1), total_count / min_lines_per_worker);
    const worker_count = @max(@as(usize, 1), @min(cpu_count, suggested_workers));

    if (worker_count == 1) {
        processRandomChunk(buffer, mixSeed(seed, 0));
        return;
    }

    var threads = try allocator.alloc(std.Thread, worker_count);
    defer allocator.free(threads);

    for (0..worker_count) |worker| {
        const start_idx = worker * total_count / worker_count;
        const end_idx = if (worker == worker_count - 1) total_count else (worker + 1) * total_count / worker_count;
        const slice_start = start_idx * line_len;
        const slice_end = end_idx * line_len;

        threads[worker] = try std.Thread.spawn(.{}, processRandomChunk, .{
            buffer[slice_start..slice_end],
            mixSeed(seed, worker + 1),
        });
    }

    for (threads) |thread| {
        thread.join();
    }
}

pub fn generatePesels(allocator: std.mem.Allocator, count: usize, seed: u64) ![]u8 {
    const buffer = try allocator.alloc(u8, count * line_len);
    errdefer allocator.free(buffer);
    try fillRandomPeselBufferParallel(allocator, buffer, seed);
    return buffer;
}

pub fn ensureRandomPeselFile(
    dir: std.Io.Dir,
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    count: usize,
) !bool {
    var file = dir.createFile(io, path, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => return false,
        else => |e| return e,
    };
    errdefer dir.deleteFile(io, path) catch {};
    defer file.close(io);

    var seed_bytes: [8]u8 = undefined;
    io.random(&seed_bytes);
    const seed = std.mem.readInt(u64, &seed_bytes, .little);

    const buffer = try generatePesels(allocator, count, seed);
    defer allocator.free(buffer);

    try file.writeStreamingAll(io, buffer);
    return true;
}

pub fn isValidPesel(pesel: []const u8) bool {
    if (pesel.len != 11) return false;

    var digits: [11]u8 = undefined;
    for (pesel, 0..) |char, index| {
        if (char < '0' or char > '9') return false;
        digits[index] = char - '0';
    }

    const encoded_month = @as(u32, digits[2]) * 10 + digits[3];
    const yy = @as(u32, digits[0]) * 10 + digits[1];
    const decoded = decodePeselMonth(encoded_month, yy) orelse return false;

    const year = decoded[0];
    const month = decoded[1];
    const day = @as(u32, digits[4]) * 10 + digits[5];
    if (day == 0 or day > daysInMonth(year, month)) return false;

    const first_ten: [10]u8 = .{
        digits[0], digits[1], digits[2], digits[3], digits[4],
        digits[5], digits[6], digits[7], digits[8], digits[9],
    };
    return checksumDigit(&first_ten) == digits[10];
}

pub const MultiplyShiftHasher = struct {
    multiplier: u64,
    bits: bucket_bits_max,

    pub fn init(bits: bucket_bits_max, multiplier: u64) MultiplyShiftHasher {
        std.debug.assert(bits > 0);
        std.debug.assert(bits < 64);
        return .{
            .multiplier = if ((multiplier | 1) == 0) 1 else (multiplier | 1),
            .bits = bits,
        };
    }

    pub fn bucketCount(self: MultiplyShiftHasher) usize {
        return @as(usize, 1) << self.bits;
    }

    pub fn hash(self: MultiplyShiftHasher, key: u64) usize {
        const shift: u6 = @intCast(@as(u8, 64) - self.bits);
        return @intCast((key *% self.multiplier) >> shift);
    }

    pub fn withBits(self: MultiplyShiftHasher, bits: bucket_bits_max) MultiplyShiftHasher {
        return init(bits, self.multiplier);
    }
};

pub const MultiplyShiftHashSet = struct {
    allocator: std.mem.Allocator,
    buckets: []?*Node,
    len: usize,
    hasher: MultiplyShiftHasher,

    const Node = struct {
        key: u64,
        next: ?*Node = null,
    };

    pub fn init(allocator: std.mem.Allocator, bits: bucket_bits_max, multiplier: u64) !MultiplyShiftHashSet {
        const hasher = MultiplyShiftHasher.init(bits, multiplier);
        const buckets = try allocator.alloc(?*Node, hasher.bucketCount());
        @memset(buckets, null);

        return .{
            .allocator = allocator,
            .buckets = buckets,
            .len = 0,
            .hasher = hasher,
        };
    }

    pub fn deinit(self: *MultiplyShiftHashSet) void {
        for (self.buckets) |head| {
            var node = head;
            while (node) |current| {
                node = current.next;
                self.allocator.destroy(current);
            }
        }
        self.allocator.free(self.buckets);
        self.* = undefined;
    }

    pub fn contains(self: *const MultiplyShiftHashSet, key: u64) bool {
        var node = self.buckets[self.hasher.hash(key)];
        while (node) |current| {
            if (current.key == key) return true;
            node = current.next;
        }
        return false;
    }

    pub fn insert(self: *MultiplyShiftHashSet, key: u64) !bool {
        if (self.contains(key)) return false;
        try self.ensureCapacityForInsert();

        const bucket_index = self.hasher.hash(key);
        const node = try self.allocator.create(Node);
        node.* = .{
            .key = key,
            .next = self.buckets[bucket_index],
        };

        self.buckets[bucket_index] = node;
        self.len += 1;
        return true;
    }

    fn ensureCapacityForInsert(self: *MultiplyShiftHashSet) !void {
        if ((self.len + 1) * 4 <= self.buckets.len * 3) return;
        if (self.hasher.bits == std.math.maxInt(bucket_bits_max)) return;
        try self.rehash(self.hasher.bits + 1);
    }

    fn rehash(self: *MultiplyShiftHashSet, new_bits: bucket_bits_max) !void {
        const new_hasher = self.hasher.withBits(new_bits);
        const new_buckets = try self.allocator.alloc(?*Node, new_hasher.bucketCount());
        @memset(new_buckets, null);

        for (self.buckets) |head| {
            var node = head;
            while (node) |current| {
                const next = current.next;
                const new_index = new_hasher.hash(current.key);
                current.next = new_buckets[new_index];
                new_buckets[new_index] = current;
                node = next;
            }
        }

        self.allocator.free(self.buckets);
        self.buckets = new_buckets;
        self.hasher = new_hasher;
    }
};

pub const AvlTree = struct {
    allocator: std.mem.Allocator,
    root: ?*Node = null,
    len: usize = 0,

    const Node = struct {
        key: u64,
        left: ?*Node = null,
        right: ?*Node = null,
        height: i32 = 1,
    };

    const InsertResult = struct {
        node: *Node,
        inserted: bool,
    };

    pub fn init(allocator: std.mem.Allocator) AvlTree {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *AvlTree) void {
        destroyNode(self.allocator, self.root);
        self.* = undefined;
    }

    pub fn contains(self: *const AvlTree, key: u64) bool {
        var current = self.root;
        while (current) |node| {
            if (key < node.key) {
                current = node.left;
            } else if (key > node.key) {
                current = node.right;
            } else {
                return true;
            }
        }
        return false;
    }

    pub fn insert(self: *AvlTree, key: u64) !bool {
        const result = try insertNode(self.allocator, self.root, key);
        self.root = result.node;
        if (result.inserted) self.len += 1;
        return result.inserted;
    }

    pub fn remove(self: *AvlTree, key: u64) !bool {
        var keys: std.ArrayList(u64) = .empty;
        defer keys.deinit(self.allocator);

        var removed = false;
        try collectKeysExcept(self.root, key, &keys, self.allocator, &removed);
        if (!removed) return false;

        var rebuilt = AvlTree.init(self.allocator);
        errdefer rebuilt.deinit();
        for (keys.items) |existing_key| {
            _ = try rebuilt.insert(existing_key);
        }

        destroyNode(self.allocator, self.root);
        self.* = rebuilt;
        return true;
    }

    pub fn writeIndented(self: *const AvlTree, writer: anytype) !void {
        if (self.root == null) {
            try writer.writeAll("(empty)\n");
            return;
        }
        try writeNodeIndented(writer, self.root, 0, "root");
    }

    pub fn serialize(self: *const AvlTree, allocator: std.mem.Allocator) ![]u8 {
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(allocator);

        try bytes.appendSlice(allocator, "AVL1");
        try serializeNode(&bytes, allocator, self.root);
        return bytes.toOwnedSlice(allocator);
    }

    pub fn deserialize(allocator: std.mem.Allocator, bytes: []const u8) !AvlTree {
        if (bytes.len < 4 or !std.mem.eql(u8, bytes[0..4], "AVL1")) {
            return TreeCodecError.InvalidFormat;
        }

        var cursor: usize = 4;
        const root = try deserializeNode(allocator, bytes, &cursor);
        errdefer destroyNode(allocator, root);

        if (cursor != bytes.len) return TreeCodecError.InvalidFormat;

        return .{
            .allocator = allocator,
            .root = root,
            .len = countNodes(root),
        };
    }

    fn insertNode(allocator: std.mem.Allocator, maybe_node: ?*Node, key: u64) !InsertResult {
        if (maybe_node == null) {
            const node = try allocator.create(Node);
            node.* = .{ .key = key };
            return .{ .node = node, .inserted = true };
        }

        var node = maybe_node.?;
        var inserted = false;

        if (key < node.key) {
            const result = try insertNode(allocator, node.left, key);
            node.left = result.node;
            inserted = result.inserted;
        } else if (key > node.key) {
            const result = try insertNode(allocator, node.right, key);
            node.right = result.node;
            inserted = result.inserted;
        } else {
            return .{ .node = node, .inserted = false };
        }

        return .{ .node = rebalance(node), .inserted = inserted };
    }

    fn destroyNode(allocator: std.mem.Allocator, maybe_node: ?*Node) void {
        if (maybe_node) |node| {
            destroyNode(allocator, node.left);
            destroyNode(allocator, node.right);
            allocator.destroy(node);
        }
    }

    fn countNodes(maybe_node: ?*Node) usize {
        const node = maybe_node orelse return 0;
        return 1 + countNodes(node.left) + countNodes(node.right);
    }

    fn collectKeysExcept(
        maybe_node: ?*Node,
        key: u64,
        keys: *std.ArrayList(u64),
        allocator: std.mem.Allocator,
        removed: *bool,
    ) !void {
        const node = maybe_node orelse return;
        try collectKeysExcept(node.left, key, keys, allocator, removed);
        if (!removed.* and node.key == key) {
            removed.* = true;
        } else {
            try keys.append(allocator, node.key);
        }
        try collectKeysExcept(node.right, key, keys, allocator, removed);
    }

    fn height(maybe_node: ?*Node) i32 {
        return if (maybe_node) |node| node.height else 0;
    }

    fn updateHeight(node: *Node) void {
        node.height = @max(height(node.left), height(node.right)) + 1;
    }

    fn balanceFactor(node: *Node) i32 {
        return height(node.left) - height(node.right);
    }

    fn rotateLeft(node: *Node) *Node {
        var new_root = node.right.?;
        node.right = new_root.left;
        new_root.left = node;
        updateHeight(node);
        updateHeight(new_root);
        return new_root;
    }

    fn rotateRight(node: *Node) *Node {
        var new_root = node.left.?;
        node.left = new_root.right;
        new_root.right = node;
        updateHeight(node);
        updateHeight(new_root);
        return new_root;
    }

    fn rebalance(node: *Node) *Node {
        updateHeight(node);
        const balance = balanceFactor(node);

        if (balance > 1) {
            if (balanceFactor(node.left.?) < 0) {
                node.left = rotateLeft(node.left.?);
            }
            return rotateRight(node);
        }

        if (balance < -1) {
            if (balanceFactor(node.right.?) > 0) {
                node.right = rotateRight(node.right.?);
            }
            return rotateLeft(node);
        }

        return node;
    }

    fn serializeNode(bytes: *std.ArrayList(u8), allocator: std.mem.Allocator, maybe_node: ?*Node) !void {
        if (maybe_node == null) {
            try writeByte(bytes, allocator, 0);
            return;
        }

        const node = maybe_node.?;
        try writeByte(bytes, allocator, 1);
        try writeU64(bytes, allocator, node.key);
        try serializeNode(bytes, allocator, node.left);
        try serializeNode(bytes, allocator, node.right);
    }

    fn deserializeNode(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?*Node {
        const tag = try readByte(bytes, cursor);
        switch (tag) {
            0 => return null,
            1 => {},
            else => return TreeCodecError.InvalidFormat,
        }

        const node = try allocator.create(Node);
        errdefer allocator.destroy(node);

        node.* = .{ .key = try readU64(bytes, cursor) };
        node.left = try deserializeNode(allocator, bytes, cursor);
        errdefer destroyNode(allocator, node.left);

        node.right = try deserializeNode(allocator, bytes, cursor);
        errdefer destroyNode(allocator, node.right);

        updateHeight(node);
        return node;
    }

    fn writeNodeIndented(writer: anytype, maybe_node: ?*Node, depth: usize, label: []const u8) !void {
        for (0..depth) |_| try writer.writeAll("  ");
        if (maybe_node == null) {
            try writer.print("{s}: null\n", .{label});
            return;
        }

        const node = maybe_node.?;
        try writer.print("{s}: key={} height={}\n", .{ label, node.key, node.height });
        try writeNodeIndented(writer, node.left, depth + 1, "L");
        try writeNodeIndented(writer, node.right, depth + 1, "R");
    }
};

pub const RedBlackTree = struct {
    allocator: std.mem.Allocator,
    root: ?*Node = null,
    len: usize = 0,

    const Color = enum { red, black };

    const Node = struct {
        key: u64,
        left: ?*Node = null,
        right: ?*Node = null,
        color: Color = .red,
    };

    const InsertResult = struct {
        node: *Node,
        inserted: bool,
    };

    pub fn init(allocator: std.mem.Allocator) RedBlackTree {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *RedBlackTree) void {
        destroyNode(self.allocator, self.root);
        self.* = undefined;
    }

    pub fn contains(self: *const RedBlackTree, key: u64) bool {
        var current = self.root;
        while (current) |node| {
            if (key < node.key) {
                current = node.left;
            } else if (key > node.key) {
                current = node.right;
            } else {
                return true;
            }
        }
        return false;
    }

    pub fn insert(self: *RedBlackTree, key: u64) !bool {
        const result = try insertNode(self.allocator, self.root, key);
        self.root = result.node;
        self.root.?.color = .black;
        if (result.inserted) self.len += 1;
        return result.inserted;
    }

    pub fn remove(self: *RedBlackTree, key: u64) !bool {
        var keys: std.ArrayList(u64) = .empty;
        defer keys.deinit(self.allocator);

        var removed = false;
        try collectKeysExcept(self.root, key, &keys, self.allocator, &removed);
        if (!removed) return false;

        var rebuilt = RedBlackTree.init(self.allocator);
        errdefer rebuilt.deinit();
        for (keys.items) |existing_key| {
            _ = try rebuilt.insert(existing_key);
        }

        destroyNode(self.allocator, self.root);
        self.* = rebuilt;
        return true;
    }

    pub fn writeIndented(self: *const RedBlackTree, writer: anytype) !void {
        if (self.root == null) {
            try writer.writeAll("(empty)\n");
            return;
        }
        try writeNodeIndented(writer, self.root, 0, "root");
    }

    pub fn serialize(self: *const RedBlackTree, allocator: std.mem.Allocator) ![]u8 {
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(allocator);

        try bytes.appendSlice(allocator, "RBT1");
        try serializeNode(&bytes, allocator, self.root);
        return bytes.toOwnedSlice(allocator);
    }

    pub fn deserialize(allocator: std.mem.Allocator, bytes: []const u8) !RedBlackTree {
        if (bytes.len < 4 or !std.mem.eql(u8, bytes[0..4], "RBT1")) {
            return TreeCodecError.InvalidFormat;
        }

        var cursor: usize = 4;
        const root = try deserializeNode(allocator, bytes, &cursor);
        errdefer destroyNode(allocator, root);

        if (cursor != bytes.len) return TreeCodecError.InvalidFormat;

        return .{
            .allocator = allocator,
            .root = root,
            .len = countNodes(root),
        };
    }

    fn insertNode(allocator: std.mem.Allocator, maybe_node: ?*Node, key: u64) !InsertResult {
        if (maybe_node == null) {
            const node = try allocator.create(Node);
            node.* = .{ .key = key };
            return .{ .node = node, .inserted = true };
        }

        var node = maybe_node.?;
        var inserted = false;

        if (key < node.key) {
            const result = try insertNode(allocator, node.left, key);
            node.left = result.node;
            inserted = result.inserted;
        } else if (key > node.key) {
            const result = try insertNode(allocator, node.right, key);
            node.right = result.node;
            inserted = result.inserted;
        } else {
            return .{ .node = node, .inserted = false };
        }

        return .{ .node = fixUp(node), .inserted = inserted };
    }

    fn destroyNode(allocator: std.mem.Allocator, maybe_node: ?*Node) void {
        if (maybe_node) |node| {
            destroyNode(allocator, node.left);
            destroyNode(allocator, node.right);
            allocator.destroy(node);
        }
    }

    fn countNodes(maybe_node: ?*Node) usize {
        const node = maybe_node orelse return 0;
        return 1 + countNodes(node.left) + countNodes(node.right);
    }

    fn collectKeysExcept(
        maybe_node: ?*Node,
        key: u64,
        keys: *std.ArrayList(u64),
        allocator: std.mem.Allocator,
        removed: *bool,
    ) !void {
        const node = maybe_node orelse return;
        try collectKeysExcept(node.left, key, keys, allocator, removed);
        if (!removed.* and node.key == key) {
            removed.* = true;
        } else {
            try keys.append(allocator, node.key);
        }
        try collectKeysExcept(node.right, key, keys, allocator, removed);
    }

    fn isRed(maybe_node: ?*Node) bool {
        return if (maybe_node) |node| node.color == .red else false;
    }

    fn rotateLeft(node: *Node) *Node {
        var new_root = node.right.?;
        node.right = new_root.left;
        new_root.left = node;
        new_root.color = node.color;
        node.color = .red;
        return new_root;
    }

    fn rotateRight(node: *Node) *Node {
        var new_root = node.left.?;
        node.left = new_root.right;
        new_root.right = node;
        new_root.color = node.color;
        node.color = .red;
        return new_root;
    }

    fn flipColors(node: *Node) void {
        node.color = switch (node.color) {
            .red => .black,
            .black => .red,
        };
        if (node.left) |left| {
            left.color = switch (left.color) {
                .red => .black,
                .black => .red,
            };
        }
        if (node.right) |right| {
            right.color = switch (right.color) {
                .red => .black,
                .black => .red,
            };
        }
    }

    fn fixUp(start: *Node) *Node {
        var node = start;

        if (isRed(node.right) and !isRed(node.left)) {
            node = rotateLeft(node);
        }
        if (isRed(node.left) and isRed(node.left.?.left)) {
            node = rotateRight(node);
        }
        if (isRed(node.left) and isRed(node.right)) {
            flipColors(node);
        }

        return node;
    }

    fn serializeNode(bytes: *std.ArrayList(u8), allocator: std.mem.Allocator, maybe_node: ?*Node) !void {
        if (maybe_node == null) {
            try writeByte(bytes, allocator, 0);
            return;
        }

        const node = maybe_node.?;
        try writeByte(bytes, allocator, 1);
        try writeU64(bytes, allocator, node.key);
        try writeByte(bytes, allocator, if (node.color == .red) 1 else 0);
        try serializeNode(bytes, allocator, node.left);
        try serializeNode(bytes, allocator, node.right);
    }

    fn deserializeNode(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?*Node {
        const tag = try readByte(bytes, cursor);
        switch (tag) {
            0 => return null,
            1 => {},
            else => return TreeCodecError.InvalidFormat,
        }

        const node = try allocator.create(Node);
        errdefer allocator.destroy(node);

        const color_tag = blk: {
            const key = try readU64(bytes, cursor);
            const raw_color = try readByte(bytes, cursor);
            const color = switch (raw_color) {
                0 => Color.black,
                1 => Color.red,
                else => return TreeCodecError.InvalidFormat,
            };
            node.* = .{ .key = key, .color = color };
            break :blk color;
        };
        _ = color_tag;

        node.left = try deserializeNode(allocator, bytes, cursor);
        errdefer destroyNode(allocator, node.left);

        node.right = try deserializeNode(allocator, bytes, cursor);
        errdefer destroyNode(allocator, node.right);

        return node;
    }

    fn writeNodeIndented(writer: anytype, maybe_node: ?*Node, depth: usize, label: []const u8) !void {
        for (0..depth) |_| try writer.writeAll("  ");
        if (maybe_node == null) {
            try writer.print("{s}: null\n", .{label});
            return;
        }

        const node = maybe_node.?;
        try writer.print("{s}: key={} color={s}\n", .{
            label,
            node.key,
            if (node.color == .red) "red" else "black",
        });
        try writeNodeIndented(writer, node.left, depth + 1, "L");
        try writeNodeIndented(writer, node.right, depth + 1, "R");
    }
};

pub const TwoThreeFourTree = struct {
    allocator: std.mem.Allocator,
    root: ?*Node = null,
    len: usize = 0,

    const Node = struct {
        key_count: u8 = 0,
        is_leaf: bool = true,
        keys: [3]u64 = .{ 0, 0, 0 },
        children: [4]?*Node = .{ null, null, null, null },
    };

    pub fn init(allocator: std.mem.Allocator) TwoThreeFourTree {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TwoThreeFourTree) void {
        destroyNode(self.allocator, self.root);
        self.* = undefined;
    }

    pub fn contains(self: *const TwoThreeFourTree, key: u64) bool {
        var current = self.root;
        while (current) |node| {
            var index: usize = 0;
            while (index < node.key_count and key > node.keys[index]) : (index += 1) {}
            if (index < node.key_count and key == node.keys[index]) return true;
            if (node.is_leaf) return false;
            current = node.children[index];
        }
        return false;
    }

    pub fn insert(self: *TwoThreeFourTree, key: u64) !bool {
        if (self.root == null) {
            const root = try createNode(self.allocator, true);
            root.keys[0] = key;
            root.key_count = 1;
            self.root = root;
            self.len = 1;
            return true;
        }

        if (self.root.?.key_count == 3) {
            const old_root = self.root.?;
            const new_root = try createNode(self.allocator, false);
            new_root.children[0] = old_root;
            try splitChild(self.allocator, new_root, 0);
            self.root = new_root;
        }

        var current = self.root.?;
        while (true) {
            var index: usize = 0;
            while (index < current.key_count and key > current.keys[index]) : (index += 1) {}
            if (index < current.key_count and key == current.keys[index]) return false;

            if (current.is_leaf) {
                insertKeyIntoNode(current, index, key);
                self.len += 1;
                return true;
            }

            if (current.children[index].?.key_count == 3) {
                try splitChild(self.allocator, current, index);
                if (key == current.keys[index]) return false;
                if (key > current.keys[index]) index += 1;
            }

            current = current.children[index].?;
        }
    }

    pub fn remove(self: *TwoThreeFourTree, key: u64) !bool {
        var keys: std.ArrayList(u64) = .empty;
        defer keys.deinit(self.allocator);

        var removed = false;
        try collectKeysExcept(self.root, key, &keys, self.allocator, &removed);
        if (!removed) return false;

        var rebuilt = TwoThreeFourTree.init(self.allocator);
        errdefer rebuilt.deinit();
        for (keys.items) |existing_key| {
            _ = try rebuilt.insert(existing_key);
        }

        destroyNode(self.allocator, self.root);
        self.* = rebuilt;
        return true;
    }

    pub fn writeIndented(self: *const TwoThreeFourTree, writer: anytype) !void {
        if (self.root == null) {
            try writer.writeAll("(empty)\n");
            return;
        }
        try writeNodeIndented(writer, self.root, 0, "root");
    }

    pub fn serialize(self: *const TwoThreeFourTree, allocator: std.mem.Allocator) ![]u8 {
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(allocator);

        try bytes.appendSlice(allocator, "2341");
        try serializeNode(&bytes, allocator, self.root);
        return bytes.toOwnedSlice(allocator);
    }

    pub fn deserialize(allocator: std.mem.Allocator, bytes: []const u8) !TwoThreeFourTree {
        if (bytes.len < 4 or !std.mem.eql(u8, bytes[0..4], "2341")) {
            return TreeCodecError.InvalidFormat;
        }

        var cursor: usize = 4;
        const root = try deserializeNode(allocator, bytes, &cursor);
        errdefer destroyNode(allocator, root);

        if (cursor != bytes.len) return TreeCodecError.InvalidFormat;

        return .{
            .allocator = allocator,
            .root = root,
            .len = countKeys(root),
        };
    }

    fn createNode(allocator: std.mem.Allocator, is_leaf: bool) !*Node {
        const node = try allocator.create(Node);
        node.* = .{ .is_leaf = is_leaf };
        return node;
    }

    fn destroyNode(allocator: std.mem.Allocator, maybe_node: ?*Node) void {
        if (maybe_node) |node| {
            if (!node.is_leaf) {
                for (node.children) |child| {
                    destroyNode(allocator, child);
                }
            }
            allocator.destroy(node);
        }
    }

    fn countKeys(maybe_node: ?*Node) usize {
        const node = maybe_node orelse return 0;
        var total: usize = node.key_count;
        if (!node.is_leaf) {
            for (0..node.key_count + 1) |child_index| {
                total += countKeys(node.children[child_index]);
            }
        }
        return total;
    }

    fn collectKeysExcept(
        maybe_node: ?*Node,
        key: u64,
        keys: *std.ArrayList(u64),
        allocator: std.mem.Allocator,
        removed: *bool,
    ) !void {
        const node = maybe_node orelse return;
        if (node.is_leaf) {
            for (0..node.key_count) |index| {
                if (!removed.* and node.keys[index] == key) {
                    removed.* = true;
                } else {
                    try keys.append(allocator, node.keys[index]);
                }
            }
            return;
        }

        for (0..node.key_count) |index| {
            try collectKeysExcept(node.children[index], key, keys, allocator, removed);
            if (!removed.* and node.keys[index] == key) {
                removed.* = true;
            } else {
                try keys.append(allocator, node.keys[index]);
            }
        }
        try collectKeysExcept(node.children[node.key_count], key, keys, allocator, removed);
    }

    fn insertKeyIntoNode(node: *Node, index: usize, key: u64) void {
        var slot = @as(usize, node.key_count);
        while (slot > index) : (slot -= 1) {
            node.keys[slot] = node.keys[slot - 1];
        }
        node.keys[index] = key;
        node.key_count += 1;
    }

    fn splitChild(allocator: std.mem.Allocator, parent: *Node, child_index: usize) !void {
        var child = parent.children[child_index].?;
        std.debug.assert(child.key_count == 3);
        std.debug.assert(parent.key_count < 3);

        const sibling = try createNode(allocator, child.is_leaf);
        sibling.key_count = 1;
        sibling.keys[0] = child.keys[2];

        if (!child.is_leaf) {
            sibling.children[0] = child.children[2];
            sibling.children[1] = child.children[3];
            child.children[2] = null;
            child.children[3] = null;
        }

        const promoted_key = child.keys[1];
        child.key_count = 1;

        var child_slot = @as(usize, parent.key_count) + 1;
        while (child_slot > child_index + 1) : (child_slot -= 1) {
            parent.children[child_slot] = parent.children[child_slot - 1];
        }
        parent.children[child_index + 1] = sibling;

        var key_slot = @as(usize, parent.key_count);
        while (key_slot > child_index) : (key_slot -= 1) {
            parent.keys[key_slot] = parent.keys[key_slot - 1];
        }
        parent.keys[child_index] = promoted_key;
        parent.key_count += 1;
    }

    fn serializeNode(bytes: *std.ArrayList(u8), allocator: std.mem.Allocator, maybe_node: ?*Node) !void {
        if (maybe_node == null) {
            try writeByte(bytes, allocator, 0);
            return;
        }

        const node = maybe_node.?;
        try writeByte(bytes, allocator, 1);
        try writeByte(bytes, allocator, node.key_count);
        try writeByte(bytes, allocator, if (node.is_leaf) 1 else 0);
        for (0..node.key_count) |index| {
            try writeU64(bytes, allocator, node.keys[index]);
        }
        if (!node.is_leaf) {
            for (0..node.key_count + 1) |index| {
                try serializeNode(bytes, allocator, node.children[index]);
            }
        }
    }

    fn deserializeNode(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?*Node {
        const tag = try readByte(bytes, cursor);
        switch (tag) {
            0 => return null,
            1 => {},
            else => return TreeCodecError.InvalidFormat,
        }

        const key_count = try readByte(bytes, cursor);
        if (key_count == 0 or key_count > 3) return TreeCodecError.InvalidFormat;

        const is_leaf = switch (try readByte(bytes, cursor)) {
            0 => false,
            1 => true,
            else => return TreeCodecError.InvalidFormat,
        };

        const node = try allocator.create(Node);
        errdefer allocator.destroy(node);
        node.* = .{ .key_count = key_count, .is_leaf = is_leaf };

        for (0..key_count) |index| {
            node.keys[index] = try readU64(bytes, cursor);
            if (index > 0 and node.keys[index - 1] >= node.keys[index]) {
                return TreeCodecError.InvalidFormat;
            }
        }

        if (!is_leaf) {
            for (0..key_count + 1) |index| {
                node.children[index] = try deserializeNode(allocator, bytes, cursor);
                errdefer {
                    var cleanup_index: usize = 0;
                    while (cleanup_index <= index) : (cleanup_index += 1) {
                        destroyNode(allocator, node.children[cleanup_index]);
                    }
                }
                if (node.children[index] == null) return TreeCodecError.InvalidFormat;
            }
        }

        return node;
    }

    fn writeNodeIndented(writer: anytype, maybe_node: ?*Node, depth: usize, label: []const u8) !void {
        for (0..depth) |_| try writer.writeAll("  ");
        if (maybe_node == null) {
            try writer.print("{s}: null\n", .{label});
            return;
        }

        const node = maybe_node.?;
        try writer.print("{s}: keys=[", .{label});
        for (0..node.key_count) |index| {
            if (index != 0) try writer.writeAll(", ");
            try writer.print("{}", .{node.keys[index]});
        }
        try writer.print("] leaf={}\n", .{node.is_leaf});

        if (!node.is_leaf) {
            for (0..node.key_count + 1) |index| {
                var child_label_buf: [8]u8 = undefined;
                const child_label = try std.fmt.bufPrint(&child_label_buf, "C{}", .{index});
                try writeNodeIndented(writer, node.children[index], depth + 1, child_label);
            }
        }
    }
};

pub const RabinKarp = struct {
    base: u64 = 257,

    pub fn init(base: u64) RabinKarp {
        return .{ .base = if (base == 0) 257 else base };
    }

    pub fn findFirst(self: RabinKarp, haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len == 0) return 0;
        if (needle.len > haystack.len) return null;
        if (needle.len == 1) return std.mem.indexOfScalar(u8, haystack, needle[0]);

        var window_hash: u64 = 0;
        var needle_hash: u64 = 0;
        var highest_power: u64 = 1;

        for (needle, 0..) |needle_byte, index| {
            needle_hash = needle_hash *% self.base +% needle_byte;
            window_hash = window_hash *% self.base +% haystack[index];
            if (index + 1 < needle.len) {
                highest_power *%= self.base;
            }
        }

        var start: usize = 0;
        while (true) {
            if (window_hash == needle_hash and verifyCandidateVectorized(
                haystack[start .. start + needle.len],
                needle,
            )) {
                return start;
            }

            if (start + needle.len == haystack.len) break;

            const outgoing = @as(u64, haystack[start]) *% highest_power;
            window_hash -%= outgoing;
            window_hash *%= self.base;
            window_hash +%= haystack[start + needle.len];
            start += 1;
        }

        return null;
    }

    pub fn findAll(self: RabinKarp, allocator: std.mem.Allocator, haystack: []const u8, needle: []const u8) ![]usize {
        if (needle.len == 0) {
            const trivial = try allocator.alloc(usize, 1);
            trivial[0] = 0;
            return trivial;
        }
        if (needle.len > haystack.len) return allocator.alloc(usize, 0);

        var matches: std.ArrayList(usize) = .empty;
        defer matches.deinit(allocator);

        var window_hash: u64 = 0;
        var needle_hash: u64 = 0;
        var highest_power: u64 = 1;

        for (needle, 0..) |needle_byte, index| {
            needle_hash = needle_hash *% self.base +% needle_byte;
            window_hash = window_hash *% self.base +% haystack[index];
            if (index + 1 < needle.len) {
                highest_power *%= self.base;
            }
        }

        var start: usize = 0;
        while (true) {
            if (window_hash == needle_hash and verifyCandidateVectorized(
                haystack[start .. start + needle.len],
                needle,
            )) {
                try matches.append(allocator, start);
            }

            if (start + needle.len == haystack.len) break;

            const outgoing = @as(u64, haystack[start]) *% highest_power;
            window_hash -%= outgoing;
            window_hash *%= self.base;
            window_hash +%= haystack[start + needle.len];
            start += 1;
        }

        return matches.toOwnedSlice(allocator);
    }

    fn verifyCandidateVectorized(candidate: []const u8, needle: []const u8) bool {
        var offset: usize = 0;
        while (offset + ByteVerifyWidth <= needle.len) : (offset += ByteVerifyWidth) {
            var lhs_block: [ByteVerifyWidth]u8 = undefined;
            var rhs_block: [ByteVerifyWidth]u8 = undefined;
            @memcpy(lhs_block[0..], candidate[offset .. offset + ByteVerifyWidth]);
            @memcpy(rhs_block[0..], needle[offset .. offset + ByteVerifyWidth]);

            const lhs: ByteVec = @bitCast(lhs_block);
            const rhs: ByteVec = @bitCast(rhs_block);
            if (@reduce(.Or, lhs != rhs)) return false;
        }

        return std.mem.eql(u8, candidate[offset..], needle[offset..]);
    }
};

test "random PESEL buffer contains valid PESEL numbers" {
    const buffer = try generatePesels(std.testing.allocator, 128, 0x1234_5678_9abc_def0);
    defer std.testing.allocator.free(buffer);

    var offset: usize = 0;
    while (offset < buffer.len) : (offset += line_len) {
        try std.testing.expectEqual(@as(u8, '\n'), buffer[offset + 11]);
        try std.testing.expect(isValidPesel(buffer[offset .. offset + 11]));
    }
}

test "ensureRandomPeselFile only generates once" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try std.testing.expect(try ensureRandomPeselFile(tmp.dir, std.testing.io, std.testing.allocator, "pesel.txt", 32));
    try std.testing.expect(!try ensureRandomPeselFile(tmp.dir, std.testing.io, std.testing.allocator, "pesel.txt", 32));

    const contents = try tmp.dir.readFileAlloc(std.testing.io, "pesel.txt", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(contents);

    try std.testing.expectEqual(@as(usize, 32 * line_len), contents.len);

    var offset: usize = 0;
    while (offset < contents.len) : (offset += line_len) {
        try std.testing.expect(isValidPesel(contents[offset .. offset + 11]));
    }
}

test "multiply-shift hash set stores unique keys" {
    var set = try MultiplyShiftHashSet.init(std.testing.allocator, 3, 0x9e37_79b9_7f4a_7c15);
    defer set.deinit();

    try std.testing.expect(try set.insert(12_345_678_901));
    try std.testing.expect(try set.insert(98_765_432_109));
    try std.testing.expect(!try set.insert(12_345_678_901));
    try std.testing.expect(set.contains(12_345_678_901));
    try std.testing.expect(set.contains(98_765_432_109));
    try std.testing.expect(!set.contains(11_111_111_111));
}

test "AVL tree stays balanced after inserts" {
    var tree = AvlTree.init(std.testing.allocator);
    defer tree.deinit();

    const values = [_]u64{ 50, 20, 70, 10, 30, 60, 80, 25, 27, 26 };
    for (values) |value| {
        _ = try tree.insert(value);
    }

    for (values) |value| {
        try std.testing.expect(tree.contains(value));
    }
    try std.testing.expect(!tree.contains(999));

    _ = try expectAvlInvariant(tree.root, null, null);
}

test "red-black tree preserves invariants after inserts" {
    var tree = RedBlackTree.init(std.testing.allocator);
    defer tree.deinit();

    const values = [_]u64{ 40, 10, 70, 5, 20, 60, 90, 15, 30, 25, 65 };
    for (values) |value| {
        _ = try tree.insert(value);
    }

    for (values) |value| {
        try std.testing.expect(tree.contains(value));
    }
    try std.testing.expect(!tree.contains(999));
    try std.testing.expect(tree.root != null);
    try std.testing.expect(tree.root.?.color == .black);

    _ = try expectRedBlackInvariant(tree.root, null, null);
}

test "2-3-4 tree preserves invariants after inserts" {
    var tree = TwoThreeFourTree.init(std.testing.allocator);
    defer tree.deinit();

    const values = [_]u64{ 40, 10, 70, 5, 20, 60, 90, 15, 30, 25, 65, 80, 95, 85 };
    for (values) |value| {
        try std.testing.expect(try tree.insert(value));
    }

    for (values) |value| {
        try std.testing.expect(tree.contains(value));
    }
    try std.testing.expect(!tree.contains(999));
    try std.testing.expect(!try tree.insert(values[0]));

    _ = try expectTwoThreeFourInvariant(tree.root, null, null);
}

test "rabin-karp finds overlapping matches" {
    const rk = RabinKarp.init(257);
    try std.testing.expectEqual(@as(?usize, 2), rk.findFirst("zzabcabcaby", "abcab"));
    try std.testing.expectEqual(@as(?usize, null), rk.findFirst("abcdef", "gh"));

    const matches = try rk.findAll(std.testing.allocator, "aaaaa", "aa");
    defer std.testing.allocator.free(matches);

    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3 }, matches);
}

test "AVL tree serialization round-trips" {
    var tree = AvlTree.init(std.testing.allocator);
    defer tree.deinit();

    const values = [_]u64{ 50, 20, 70, 10, 30, 60, 80, 25, 27, 26 };
    for (values) |value| _ = try tree.insert(value);

    const encoded = try tree.serialize(std.testing.allocator);
    defer std.testing.allocator.free(encoded);

    var decoded = try AvlTree.deserialize(std.testing.allocator, encoded);
    defer decoded.deinit();

    const reencoded = try decoded.serialize(std.testing.allocator);
    defer std.testing.allocator.free(reencoded);

    try std.testing.expectEqual(tree.len, decoded.len);
    try std.testing.expectEqualSlices(u8, encoded, reencoded);
    _ = try expectAvlInvariant(decoded.root, null, null);
}

test "red-black tree serialization round-trips" {
    var tree = RedBlackTree.init(std.testing.allocator);
    defer tree.deinit();

    const values = [_]u64{ 40, 10, 70, 5, 20, 60, 90, 15, 30, 25, 65 };
    for (values) |value| _ = try tree.insert(value);

    const encoded = try tree.serialize(std.testing.allocator);
    defer std.testing.allocator.free(encoded);

    var decoded = try RedBlackTree.deserialize(std.testing.allocator, encoded);
    defer decoded.deinit();

    const reencoded = try decoded.serialize(std.testing.allocator);
    defer std.testing.allocator.free(reencoded);

    try std.testing.expectEqual(tree.len, decoded.len);
    try std.testing.expectEqualSlices(u8, encoded, reencoded);
    _ = try expectRedBlackInvariant(decoded.root, null, null);
}

test "2-3-4 tree serialization round-trips" {
    var tree = TwoThreeFourTree.init(std.testing.allocator);
    defer tree.deinit();

    const values = [_]u64{ 40, 10, 70, 5, 20, 60, 90, 15, 30, 25, 65, 80, 95, 85 };
    for (values) |value| _ = try tree.insert(value);

    const encoded = try tree.serialize(std.testing.allocator);
    defer std.testing.allocator.free(encoded);

    var decoded = try TwoThreeFourTree.deserialize(std.testing.allocator, encoded);
    defer decoded.deinit();

    const reencoded = try decoded.serialize(std.testing.allocator);
    defer std.testing.allocator.free(reencoded);

    try std.testing.expectEqual(tree.len, decoded.len);
    try std.testing.expectEqualSlices(u8, encoded, reencoded);
    _ = try expectTwoThreeFourInvariant(decoded.root, null, null);
}

fn writeByte(bytes: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u8) !void {
    try bytes.append(allocator, value);
}

fn writeU64(bytes: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .little);
    try bytes.appendSlice(allocator, &buf);
}

fn readByte(bytes: []const u8, cursor: *usize) TreeCodecError!u8 {
    if (cursor.* >= bytes.len) return TreeCodecError.UnexpectedEof;
    const value = bytes[cursor.*];
    cursor.* += 1;
    return value;
}

fn readU64(bytes: []const u8, cursor: *usize) TreeCodecError!u64 {
    if (bytes.len - cursor.* < 8) return TreeCodecError.UnexpectedEof;
    const slice = bytes[cursor.* .. cursor.* + 8];
    cursor.* += 8;
    return std.mem.readInt(u64, slice[0..8], .little);
}

fn expectAvlInvariant(maybe_node: ?*AvlTree.Node, min: ?u64, max: ?u64) !i32 {
    if (maybe_node == null) return 0;

    const node = maybe_node.?;
    if (min) |lo| try std.testing.expect(lo < node.key);
    if (max) |hi| try std.testing.expect(node.key < hi);

    const left_height = try expectAvlInvariant(node.left, min, node.key);
    const right_height = try expectAvlInvariant(node.right, node.key, max);
    const diff = left_height - right_height;

    try std.testing.expect(diff >= -1 and diff <= 1);
    try std.testing.expectEqual(@max(left_height, right_height) + 1, node.height);
    return node.height;
}

fn expectRedBlackInvariant(maybe_node: ?*RedBlackTree.Node, min: ?u64, max: ?u64) !usize {
    if (maybe_node == null) return 1;

    const node = maybe_node.?;
    if (min) |lo| try std.testing.expect(lo < node.key);
    if (max) |hi| try std.testing.expect(node.key < hi);

    if (node.color == .red) {
        try std.testing.expect(!RedBlackTree.isRed(node.left));
        try std.testing.expect(!RedBlackTree.isRed(node.right));
    }

    const left_black_height = try expectRedBlackInvariant(node.left, min, node.key);
    const right_black_height = try expectRedBlackInvariant(node.right, node.key, max);
    try std.testing.expectEqual(left_black_height, right_black_height);

    return left_black_height + @as(usize, if (node.color == .black) 1 else 0);
}

fn expectTwoThreeFourInvariant(maybe_node: ?*TwoThreeFourTree.Node, min: ?u64, max: ?u64) !usize {
    const node = maybe_node orelse return 0;

    try std.testing.expect(node.key_count >= 1 and node.key_count <= 3);
    for (1..node.key_count) |index| {
        try std.testing.expect(node.keys[index - 1] < node.keys[index]);
    }

    if (min) |lo| try std.testing.expect(lo < node.keys[0]);
    if (max) |hi| try std.testing.expect(node.keys[node.key_count - 1] < hi);

    if (node.is_leaf) {
        for (node.children) |child| {
            try std.testing.expect(child == null);
        }
        return 1;
    }

    for (0..node.key_count + 1) |child_index| {
        try std.testing.expect(node.children[child_index] != null);
    }
    for (node.key_count + 1..node.children.len) |child_index| {
        try std.testing.expect(node.children[child_index] == null);
    }

    var expected_height: ?usize = null;
    for (0..node.key_count + 1) |child_index| {
        const child_min = if (child_index == 0) min else node.keys[child_index - 1];
        const child_max = if (child_index == node.key_count) max else node.keys[child_index];
        const child_height = try expectTwoThreeFourInvariant(node.children[child_index], child_min, child_max);

        if (expected_height) |height| {
            try std.testing.expectEqual(height, child_height);
        } else {
            expected_height = child_height;
        }
    }

    return expected_height.? + 1;
}
