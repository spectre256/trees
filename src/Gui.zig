const std = @import("std");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
});

window: *c.SDL_Window,
renderer: *c.SDL_Renderer,
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

    return self;
}

pub fn run(self: *Self) void {
    var go = true;
    var event: c.SDL_Event = undefined;

    while (go) {
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => go = false,
                else => {},
            }
        }

        _ = c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(self.renderer);
        self.render();
        _ = c.SDL_RenderPresent(self.renderer);
    }
}

fn render(self: *Self) void {
    const color: c.SDL_Color = .{ .r = 255, .g = 255, .b = 255, .a = c.SDL_ALPHA_OPAQUE };
    const text = c.TTF_RenderText_Blended(self.font, "Hello, world!", 0, color) orelse return;
    defer c.SDL_DestroySurface(text);
    const texture = c.SDL_CreateTextureFromSurface(self.renderer, text);
    defer c.SDL_DestroyTexture(texture);

    const scale: f32 = 4.0;
    var w: c_int = undefined;
    var h: c_int = undefined;
    var dst: c.SDL_FRect = undefined;
    _ = c.SDL_GetRenderOutputSize(self.renderer, &w, &h);
    _ = c.SDL_SetRenderScale(self.renderer, scale, scale);
    _ = c.SDL_GetTextureSize(texture, &dst.w, &dst.h);
    dst.x = (@as(f32, @floatFromInt(w)) / scale - dst.w) / 2;
    dst.y = (@as(f32, @floatFromInt(h)) / scale - dst.h) / 2;
    _ = c.SDL_RenderTexture(self.renderer, texture, null, &dst);
}

pub fn deinit(self: *Self) void {
    c.TTF_CloseFont(self.font);
    c.TTF_Quit();
    c.SDL_DestroyRenderer(self.renderer);
    c.SDL_DestroyWindow(self.window);
}
