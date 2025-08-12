const std = @import("std");
const Allocator = std.mem.Allocator;
const Renderer = @import("Renderer.zig");
const Buffer = @import("Buffer.zig");
const input = @import("input.zig");

renderer: Renderer,
buffers: std.ArrayListUnmanaged(Buffer),
buffer_i: usize,
alloc: Allocator,

const Self = @This();

pub fn init(alloc: Allocator) !Self {
    var self: Self = .{
        .renderer = try .init(.{}),
        .buffers = .empty,
        .buffer_i = 0,
        .alloc = alloc,
    };

    try self.newBuffer();

    return self;
}

pub fn deinit(self: *Self) void {
    self.renderer.deinit();
    for (self.buffers.items) |*buf| buf.deinit();
    self.buffers.deinit(self.alloc);
}

pub inline fn buffer(self: *const Self) *Buffer {
    return &self.buffers.items[self.buffer_i];
}

pub fn newBuffer(self: *Self) !void {
    try self.buffers.append(self.alloc, .init(self.alloc));
    self.buffer_i = self.buffers.items.len - 1;
}

pub fn run(self: *Self) void {
    var go = true;

    while (go) {
        while (input.getEvent()) |event| {
            switch (event) {
                .quit => go = false,
                else => {},
            }
        }

        self.render();
    }
}

fn render(self: *Self) void {
    self.renderer.clear();
    self.renderer.renderText("Hello, world!", 0, 0);
    self.renderer.present();
}
