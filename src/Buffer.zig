const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Rope = @import("Rope.zig");

text: Rope,
file: ?File = null,
raw: []align(std.heap.page_size_min) u8,
cursor: Cursor,

const Self = @This();
const Cursor = struct {
    offset: usize,
    line: usize,
    col: usize,
    virtual_col: usize,

    pub const default: Cursor = .{
        .offset = 0,
        .line = 0,
        .col = 0,
        .virtual_col = 0,
    };
};

pub fn init(alloc: Allocator) Self {
    return .{
        .text = .init(alloc),
        .raw = "",
        .cursor = .default,
    };
}

pub fn deinit(self: *Self) void {
    self.text.deinit();
    if (self.file != null) self.close();
}

// Opens file
// Clears existing content if any
pub fn open(self: *Self, filename: []const u8) !void {
    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_write });
    const size = try file.getEndPos();
    self.raw = try posix.mmap(null, size, posix.PROT.READ | posix.PROT.WRITE, .{ .TYPE = .SHARED, .POPULATE = true }, file.handle, 0);
    self.file = file;
    errdefer self.close();

    // TODO: Undo/redo integration
    if (!self.text.isEmpty()) self.text.clear();
    try self.text.insert(0, self.raw);
}

// Closes file and resets buffer
pub fn close(self: *Self) void {
    if (self.file == null) return;
    posix.munmap(self.raw);
    self.raw = "";
    self.file.?.close();
    self.file = null;
    self.text.clear();
}
