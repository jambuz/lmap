const std = @import("std");

///  Linux process map parser
pub const ProcessMapParser = struct {
    proc_maps_file: std.fs.File,
    reader: std.fs.File.Reader,

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

    pub fn init(pid: ?std.posix.pid_t, buf: []u8) !@This() {
        const maps_file_path = blk: {
            if (pid) |p| {
                var buffer: [32]u8 = undefined;
                const path = try std.fmt.bufPrint(&buffer, "/proc/{}/maps", .{p});
                break :blk path;
            }
            break :blk "/proc/self/maps";
        };

        const maps_file = try std.fs.openFileAbsolute(maps_file_path, .{ .mode = .read_only });
        const reader = maps_file.reader(buf);

        return .{
            .proc_maps_file = maps_file,
            .reader = reader,
        };
    }

    pub fn next(self: *@This()) !?Map {
        const line = try self.reader.interface.takeDelimiter('\n');
        if (line) |l| {
            var tokens = std.mem.tokenizeScalar(u8, l, ' ');

            const mem_range_str = tokens.next() orelse unreachable;
            const dash_index = std.mem.indexOfScalar(u8, mem_range_str, '-').?;
            const start = std.fmt.parseInt(usize, mem_range_str[0..dash_index], 16) catch return error.FailedToParseStartAddress;
            const end = std.fmt.parseInt(usize, mem_range_str[dash_index + 1 ..], 16) catch return error.FailedToParseEndAddress;

            const perms_str = tokens.next() orelse return error.FailedToParsePermissions;
            var perms = Perms{};
            for (perms_str) |ch| {
                switch (ch) {
                    'r' => perms.read = true,
                    'w' => perms.write = true,
                    'x' => perms.execute = true,
                    'p' => perms.private = true,
                    inline else => {},
                }
            }

            _ = tokens.next();
            _ = tokens.next();
            _ = tokens.next();
            const path = std.mem.trim(u8, tokens.rest(), " ");

            return Map{
                .start = start,
                .end = end,
                .perms = perms,
                .path = path,
            };
        } else {
            return null;
        }
    }

    pub fn deinit(self: *@This()) void {
        self.proc_maps_file.close();
        self.* = undefined;
    }
};

test "Log all Maps of own process" {
    var buf: [4096]u8 = undefined;
    var p = try ProcessMapParser.init(1840, &buf);
    defer p.deinit();

    while (try p.next()) |l| {
        std.debug.print("{s} at {x}\n", .{ l.path, l.start });
    }
}
