const std = @import("std");

///  Linux process map parser
///
/// **Example usage**:
/// `var parser = try ProcessMapParser(64, 1 * 1024 * 1024).init(2732);`
/// `defer parser.deinit();`
pub fn ProcessMapParser(
    comptime max_maps: usize,
    comptime max_maps_file_len: usize,
) type {
    return struct {
        maps: std.ArrayList(Map),

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
            path: [std.posix.PATH_MAX]u8,
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
            var maps_buf: [max_maps]Map = undefined;
            var maps = std.ArrayList(Map).initBuffer(&maps_buf);
            while (maps_split.next()) |m| {
                if (m.len == 0) break;
                try maps.appendBounded(try parseLine(m));
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
            var map: Map = .{ .start = start, .end = end, .perms = perms, .path = undefined };
            std.mem.copyForwards(u8, map.path[0..trimmed_path.len], trimmed_path);

            return map;
        }

        pub fn deinit(self: *@This()) void {
            self.* = undefined;
        }
    };
}

test "Log all Maps of own process" {
    var p = try ProcessMapParser(64, 1 * 1024 * 1024).init(2732);
    defer p.deinit();

    for (p.maps.items) |map| std.debug.print("Map: 0x{x}-0x{x} {s}\n", .{ map.start, map.end, map.path });
}
