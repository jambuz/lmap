const std = @import("std");

/// Linux process map parser
pub fn ProcessMapParser(comptime max_maps: usize, comptime max_maps_file_len: usize) type {
    return struct {
        maps: [max_maps]Map = undefined,

        const Perms = struct {
            read: bool = false,
            write: bool = false,
            execute: bool = false,
            private: bool = false,
        };

        const Map = struct {
            start: usize,
            end: usize,
            perms: Perms,
            path: []const u8,
        };

        // TODO: read all file contents into a fixed buf, then use std.mem.split for the final structure.
        pub fn init(comptime pid: ?std.posix.pid_t) !@This() {
            const maps_file_path = blk: {
                if (pid) |p| break :blk std.fmt.comptimePrint("/proc/{}/maps", .{p});
                break :blk "/proc/self/maps";
            };

            const maps_file = try std.fs.openFileAbsolute(maps_file_path, .{ .mode = .read_only });
            defer maps_file.close();

            var reader_buf: [max_maps_file_len]u8 = undefined;
            var reader = maps_file.reader(&reader_buf);
            const read_len = try reader.read(&reader_buf);

            var maps_split = std.mem.splitScalar(u8, reader_buf[0..read_len], '\n');
            var maps: [max_maps]Map = undefined;
            while (maps_split.next()) |m| {
                if (maps_split.index) |i| {
                    const parsed = try parseLine(m);
                    maps[i] = parsed;
                }
            }

            return .{
                .maps = maps,
            };
        }

        fn parseLine(line: []const u8) !Map {
            var tokens = std.mem.tokenizeScalar(u8, line, ' ');

            const mem_range_str = tokens.next() orelse return error.FailedToParseMemRange;
            var mem_range = std.mem.splitScalar(u8, mem_range_str, '-');

            const start = std.fmt.parseInt(usize, mem_range.next() orelse unreachable, 16) catch return error.FailedToParseStartAddress;
            const end = std.fmt.parseInt(usize, mem_range.next() orelse unreachable, 16) catch return error.FailedToParseEndAddress;

            const perms_str = tokens.next() orelse return error.FailedToParsePermissions;
            var perms = Perms{};
            for (perms_str) |ch| {
                switch (ch) {
                    'r' => perms.read = true,
                    'w' => perms.write = true,
                    'x' => perms.execute = true,
                    'p' => perms.private = true,
                    else => {},
                }
            }

            _ = tokens.next();
            _ = tokens.next();
            _ = tokens.next();

            const trimmed_path = std.mem.trim(u8, tokens.rest(), " ");
            const path = trimmed_path;

            return Map{
                .start = start,
                .end = end,
                .perms = perms,
                .path = path,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.* = undefined;
        }
    };
}

test "Log all Maps of own process" {
    var p = try ProcessMapParser(128, 1 * 1024 * 1024).init(1706);
    defer p.deinit();

    std.debug.print("{s}\n", .{p.maps});

    // const maps = p.maps.items;
    // for (maps) |map| {
    //     std.debug.print("{s}\n", .{map.path});
    // }
}
