const std = @import("std");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

window: *c.SDL_Window,
renderer: *c.SDL_Renderer,
text_engine: *c.TTF_TextEngine,
font: *c.TTF_Font,

const Self = @This();
pub const window_size: [2]u32 = .{ 720, 1080 };
pub const window_title: [:0]const u8 = "Zinc";
const font_data = @embedFile("iosevka.ttf");
pub const WindowOptions = struct {
    fullscreen: bool = false,

    pub fn toBitmask(self: WindowOptions) u64 {
        return if (self.fullscreen) c.SDL_WINDOW_FULLSCREEN else 0;
    }
};

pub fn init(options: WindowOptions) !Self {
    var self: Self = undefined;

    var window: ?*c.SDL_Window = undefined;
    var renderer: ?*c.SDL_Renderer = undefined;
    if (!c.SDL_CreateWindowAndRenderer(window_title, window_size[1], window_size[0], options.toBitmask(), &window, &renderer)) {
        std.log.err("Couldn't create window and renderer: {s}\n", .{c.SDL_GetError()});
        return error.FailedCreateWindowRenderer;
    }
    self.window = window.?;
    self.renderer = renderer.?;

    if (!c.TTF_Init()) {
        std.log.err("Couldn't initialize fonts: {s}\n", .{c.SDL_GetError()});
        return error.FailedInitFonts;
    }

    self.font = c.TTF_OpenFontIO(c.SDL_IOFromConstMem(font_data.ptr, font_data.len), true, 18.0) orelse {
        std.log.err("Couldn't load font: {s}\n", .{c.SDL_GetError()});
        return error.FailedLoadFont;
    };

    self.text_engine = c.TTF_CreateRendererTextEngine(self.renderer) orelse {
        std.log.err("Couldn't create text engine: {s}\n", .{c.SDL_GetError()});
        return error.FailedCreateTextEngine;
    };

    return self;
}

pub fn deinit(self: *Self) void {
    c.TTF_CloseFont(self.font);
    c.TTF_Quit();
    c.SDL_DestroyRenderer(self.renderer);
    c.SDL_DestroyWindow(self.window);
}

pub fn setColor(self: *Self, r: u8, g: u8, b: u8, a: u8) void {
    _ = c.SDL_SetRenderDrawColor(self.renderer, r, g, b, a);
}

pub fn clear(self: *Self) void {
    _ = c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 255);
    _ = c.SDL_RenderClear(self.renderer);
}

pub fn present(self: *Self) void {
    _ = c.SDL_RenderPresent(self.renderer);
}

pub fn renderText(self: *Self, str: []const u8, x: f32, y: f32) !f32 {
    const text = c.TTF_CreateText(self.text_engine, self.font, str.ptr, str.len) orelse return error.FailedCreateText;
    var width: c_int = undefined;
    if (!c.TTF_GetTextSize(text, &width, null)) {
        std.log.err("Couldn't get size of text: {s}\n", .{c.SDL_GetError()});
        return error.FailedTextSize;
    }

    if (!c.TTF_DrawRendererText(text, x, y)) {
        std.log.err("Failed to render text: {s}\n", .{c.SDL_GetError()});
        return error.FailedRenderText;
    }

    return @floatFromInt(width);
}

pub fn renderRect(self: *Self, x: f32, y: f32, w: f32, h: f32) !void {
    if (!c.SDL_RenderFillRect(self.renderer, &.{ .x = x, .y = y, .w = w, .h = h })) {
        std.log.err("Failed to render rect: {s}\n", .{c.SDL_GetError()});
        return error.FailedRenderRect;
    }
}

pub inline fn textRenderer(self: *Self) TextRenderer {
    return .init(self);
}

pub const TextRenderer = struct {
    x: f32,
    y: f32,
    line_height: f32,
    renderer: *Self,

    pub fn init(renderer: *Self) TextRenderer {
        return .{
            .x = 0,
            .y = 0,
            .line_height = @floatFromInt(c.TTF_GetFontHeight(renderer.font)),
            .renderer = renderer,
        };
    }

    pub fn write(self: *TextRenderer, str: []const u8) !void {
        // Necessary because for some reason the width of an empty string is
        // the same as the width of the entire file. Perhaps SDL3_ttf looks
        // for a null character and is ignoring the length I pass it?
        if (str.len == 0) return;

        self.x += try self.renderer.renderText(str, self.x, self.y);
    }

    pub fn nextLn(self: *TextRenderer) void {
        self.y += self.line_height;
        self.x = 0;
    }
};
