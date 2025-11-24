const std = @import("std");
const c = @import("../c.zig").c;
const GfxContext = @import("../engine/gfx.zig").GfxContext;
const Input = @import("../engine/input.zig").Input;

pub const App = struct {
    window: *c.SDL_Window,
    gfx: GfxContext,
    input: Input,
    is_running: bool,

    pub fn init() !App {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
            c.SDL_Log("SDL Init Failed: %s", c.SDL_GetError());
            return error.SdlInitFailed;
        }

        const window = c.SDL_CreateWindow("Zenith", 1270, 720, c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_FULLSCREEN) orelse {
            c.SDL_Log("Window Init Failed: %s", c.SDL_GetError());
            return error.WindowInitFailed;
        };

        const gfx = try GfxContext.init(window);
        const input = Input.init(window);

        return App{
            .window = window,
            .gfx = gfx,
            .input = input,
            .is_running = true,
        };
    }

    pub fn deinit(self: *App) void {
        self.gfx.deinit();
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    pub fn pollEvents(self: *App) void {
        self.input.newFrame();
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => self.is_running = false,
                else => {},
            }
            self.input.handleEvent(&event);
        }
    }
};
