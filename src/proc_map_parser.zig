const std = @import("std");

/// Linux process map parser
pub const ProcessMapParser = struct {
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    /// Populated on initialization
    /// Contains modules' base address
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
        path: []const u8,
    };

    pub const MAX_MAPS_LINE_LEN = 256;

    pub fn init(allocator: std.mem.Allocator, pid: ?std.posix.pid_t) !ProcessMapParser {
        var arena = std.heap.ArenaAllocator.init(allocator);

        var maps = std.ArrayList(Map).init(arena.allocator());

        const maps_file_path = if (pid) |p|
            try std.fmt.allocPrint(arena.allocator(), "/proc/{d}/maps", .{p})
        else
            "/proc/self/maps";

        const maps_file = try std.fs.openFileAbsolute(maps_file_path, .{ .mode = .read_only });
        defer maps_file.close();

        var buf: [MAX_MAPS_LINE_LEN]u8 = undefined;
        var reader = std.io.bufferedReader(maps_file.reader());
        while (try reader.reader().readUntilDelimiterOrEof(&buf, '\n')) |line| {
            if (try parseLine(arena.allocator(), line)) |map| try maps.append(map);
        }

        return ProcessMapParser{
            .arena = arena,
            .allocator = arena.allocator(),
            .maps = maps,
        };
    }

    fn parseLine(allocator: std.mem.Allocator, line: []const u8) !?Map {
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');

        const mem_range_str = tokens.next() orelse return null;
        var mem_range = std.mem.splitScalar(u8, mem_range_str, '-');

        const start = std.fmt.parseInt(usize, mem_range.next() orelse return null, 16) catch return error.FailedToParseStartAddress;
        const end = std.fmt.parseInt(usize, mem_range.next() orelse return null, 16) catch return error.FailedToParseEndAddress;

        const perms_str = tokens.next() orelse return null;
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
        const path = try allocator.dupe(u8, trimmed_path);

        return Map{
            .start = start,
            .end = end,
            .perms = perms,
            .path = path,
        };
    }

    pub fn deinit(self: *ProcessMapParser) void {
        self.arena.deinit();
    }
};

test "Log all Maps of own process" {
    const allocator = std.testing.allocator;

    var p = try ProcessMapParser.init(allocator, null);
    defer p.deinit();

    const maps = p.maps.items;
    for (maps) |map| {
        std.debug.print("{s}\n", .{map.path});
    }
}
