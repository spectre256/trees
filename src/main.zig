const std = @import("std");
const Gui = @import("Gui.zig");

pub fn main() !void {
    var gui: Gui = try .init(.{});
    defer gui.deinit();

    gui.run();
}
