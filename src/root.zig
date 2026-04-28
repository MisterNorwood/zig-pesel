const std = @import("std");

const Vec = @Vector(8, u32);

pub fn generatePesels(allocator: std.mem.Allocator) ![]u8 {
    const count = 40_000_000;
    // Each PESEL is 11 bytes. Total ~440MB.
    const buffer = try allocator.alloc(u8, count * 11);

    const weights = [10]u32{ 1, 3, 7, 9, 1, 3, 7, 9, 1, 3 };

    var i: usize = 0;
    while (i < count) : (i += 8) {
        // 1. Generate/Load 10 digits for 8 PESELs (Simplified for demo)
        // In practice, you'd increment date components here
        var digits: [10]Vec = undefined;
        inline for (0..10) |d| {
            digits[d] = @splat(@as(u32, 5)); // Placeholder for actual digit logic
        }

        // 2. SIMD Checksum Calculation
        var sum: Vec = @splat(@as(u32, 0));
        inline for (0..10) |d| {
            sum += digits[d] * @as(Vec, @splat(weights[d]));
        }

        const s = sum % @as(Vec, @splat(10));
        const checksum = (@as(Vec, @splat(10)) - s) % @as(Vec, @splat(10));

        inline for (0..8) |lane| {
            if (i + lane >= count) break;
            const offset = (i + lane) * 11;
            for (0..10) |d| {
                buffer[offset + d] = @as(u8, @intCast(digits[d][lane])) + '0';
            }
            buffer[offset + 10] = @as(u8, @intCast(checksum[lane])) + '0';
        }
    }
    return buffer;
}
