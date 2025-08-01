const std = @import("std");

/// Process map parser using arena allocator for simple memory management
pub const ProcessMapParser = struct {
    arena: std.heap.ArenaAllocator,
    maps: std.StringHashMap(Map),

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

    const MAX_MAPS_LINE_LEN = 256;

    pub fn init(allocator: std.mem.Allocator, pid: ?std.posix.pid_t) !ProcessMapParser {
        var arena = std.heap.ArenaAllocator.init(allocator);
        var maps = std.StringHashMap(Map).init(arena.allocator());

        const maps_file_path = if (pid) |p|
            try std.fmt.allocPrint(arena.allocator(), "/proc/{d}/maps", .{p})
        else
            "/proc/self/maps";

        const maps_file = try std.fs.openFileAbsolute(maps_file_path, .{ .mode = .read_only });
        defer maps_file.close();

        var buf: [MAX_MAPS_LINE_LEN]u8 = undefined;
        var reader = std.io.bufferedReader(maps_file.reader());

        while (try reader.reader().readUntilDelimiterOrEof(&buf, '\n')) |line| {
            if (try parseLine(line)) |map| {
                const owned_path = try arena.allocator().dupe(u8, map.path);
                var owned_map = map;
                owned_map.path = owned_path;
                try maps.put(owned_path, owned_map);
            }
        }

        return ProcessMapParser{
            .arena = arena,
            .maps = maps,
        };
    }

    inline fn parseLine(line: []const u8) !?Map {
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');

        // Parse memory range
        const mem_range_str = tokens.next() orelse return null;
        var mem_range = std.mem.splitScalar(u8, mem_range_str, '-');

        const start = std.fmt.parseInt(usize, mem_range.next() orelse return null, 16) catch return null;
        const end = std.fmt.parseInt(usize, mem_range.next() orelse return null, 16) catch return null;

        // Parse permissions
        const perms_str = tokens.next() orelse return null;
        var perms = Perms{};
        for (perms_str) |ch| {
            switch (ch) {
                'r' => perms.read = true,
                'w' => perms.write = true,
                'x' => perms.execute = true,
                'p' => perms.private = true,
                's' => perms.private = false,
                else => {},
            }
        }

        // Skip offset, device, inode
        _ = tokens.next();
        _ = tokens.next();
        _ = tokens.next();

        // Get path - return slice, let caller decide ownership
        const path = std.mem.trim(u8, tokens.rest(), " ");
        if (path.len == 0) return null;

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

    /// Obtains the Map entry given a path to the module on disk.
    /// E.g. /apex/com.android.runtime/lib64/bionic/libc.so
    pub inline fn getMapByPath(self: *const ProcessMapParser, path: []const u8) !Map {
        return self.maps.get(path) orelse error.MapNotFound;
    }
};

test "Test all maps" {
    const allocator = std.testing.allocator;

    var parser = try ProcessMapParser.init(allocator, null);
    defer parser.deinit();

    var it = parser.maps.iterator();
    while (it.next()) |entry| {
        std.debug.print("Map: {s} -> 0x{x}-0x{x}\n", .{ entry.key_ptr.*, entry.value_ptr.start, entry.value_ptr.end });
    }
}
