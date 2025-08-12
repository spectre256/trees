const std = @import("std");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

pub const Event = enum {
    unknown,
    quit,
};

pub fn getEvent() ?Event {
    var event: c.SDL_Event = undefined;
    if (!c.SDL_PollEvent(&event)) return null;

    return switch (event.type) {
        c.SDL_EVENT_QUIT => .quit,
        else => .unknown,
    };
}
