const std = @import("std");
const Editor = @import("Editor.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var editor: Editor = try .init(alloc);
    defer editor.deinit();

    try editor.buffer().open("src/main.zig");
    editor.run();
}
