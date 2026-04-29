const std = @import("std");

const Vec = @Vector(16, u32);

fn daysToDate(days_since_1970: usize) [3]u32 {
    var days = @as(u32, @intCast(days_since_1970));
    var year: u32 = 1970;

    while (true) {
        const is_leap = (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
        const days_in_year: u32 = if (is_leap) 366 else 365;
        if (days < days_in_year) break;
        days -= days_in_year;
        year += 1;
    }

    const is_leap = (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
    const days_in_months = [_]u32{ 31, if (is_leap) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    var month: u32 = 1;
    for (days_in_months) |dim| {
        if (days < dim) break;
        days -= dim;
        month += 1;
    }

    return .{ year, month, days + 1 };
}

fn processChunk(buffer_slice: []u8, global_start_idx: usize) void {
    const count = buffer_slice.len / 12;

    const weights = [_]u32{ 1, 3, 7, 9, 1, 3, 7, 9, 1, 3 };
    var v_weights: [10]Vec = undefined;
    inline for (0..10) |i| v_weights[i] = @splat(weights[i]);

    const v10: Vec = @splat(10);
    const v0: Vec = @splat(0);

    var i: usize = 0;
    while (i < count) : (i += 8) {
        var digits: [10]Vec = undefined;
        inline for (0..10) |d| digits[d] = v0;

        inline for (0..8) |lane| {
            const absolute_idx = global_start_idx + i + lane;

            const days_offset = absolute_idx / 10000;
            const serial = @as(u32, @intCast(absolute_idx % 10000));

            const date = daysToDate(days_offset);
            const y = date[0];
            var m = date[1];
            const d = date[2];

            if (y >= 2000 and y <= 2099) {
                m += 20;
            } else if (y >= 2100 and y <= 2199) {
                m += 40;
            }

            digits[0][lane] = (y % 100) / 10;
            digits[1][lane] = (y % 100) % 10;
            digits[2][lane] = m / 10;
            digits[3][lane] = m % 10;
            digits[4][lane] = d / 10;
            digits[5][lane] = d % 10;

            digits[6][lane] = serial / 1000;
            digits[7][lane] = (serial / 100) % 10;
            digits[8][lane] = (serial / 10) % 10;
            digits[9][lane] = serial % 10;
        }

        var sum: Vec = v0;
        inline for (0..10) |d| sum += digits[d] * v_weights[d];

        // PESEL Checksum formula: (10 - (Sum % 10)) % 10
        const s = sum % v10;
        const checksum = (v10 - s) % v10;

        inline for (0..8) |lane| {
            if (i + lane >= count) break;
            const offset = (i + lane) * 12;
            inline for (0..10) |d| {
                buffer_slice[offset + d] = @as(u8, @intCast(digits[d][lane])) + '0';
            }
            buffer_slice[offset + 10] = @as(u8, @intCast(checksum[lane])) + '0';
            buffer_slice[offset + 11] = '\n';
        }
    }
}

pub fn generatePesels(allocator: std.mem.Allocator) ![]u8 {
    const total_count = 400_000_000;
    const buffer = try allocator.alloc(u8, total_count * 12);

    const cpu_count = try std.Thread.getCpuCount();
    const chunk_size = total_count / cpu_count;

    var threads = try allocator.alloc(std.Thread, cpu_count);
    defer allocator.free(threads);

    for (0..cpu_count) |t| {
        const start_idx = t * chunk_size;
        const end_idx = if (t == cpu_count - 1) total_count else start_idx + chunk_size;

        const slice_start = start_idx * 12;
        const slice_end = end_idx * 12;

        threads[t] = try std.Thread.spawn(.{}, processChunk, .{ buffer[slice_start..slice_end], start_idx });
    }

    for (threads) |thread| {
        thread.join();
    }

    return buffer;
}
