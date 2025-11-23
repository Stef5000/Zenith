const std = @import("std");
const c = @import("../c.zig").c;

pub const Input = struct {
    keyboard: [*]const bool,
    mouse_delta_x: f32,
    mouse_delta_y: f32,

    pub fn init(window: *c.SDL_Window) Input {
        _ = c.SDL_SetWindowRelativeMouseMode(window, true);
        var num_keys: i32 = 0;
        const keys = c.SDL_GetKeyboardState(&num_keys);

        return Input{
            .keyboard = keys,
            .mouse_delta_x = 0,
            .mouse_delta_y = 0,
        };
    }

    pub fn newFrame(self: *Input) void {
        self.mouse_delta_x = 0;
        self.mouse_delta_y = 0;
    }

    pub fn handleEvent(self: *Input, event: *c.SDL_Event) void {
        if (event.type == c.SDL_EVENT_MOUSE_MOTION) {
            self.mouse_delta_x += event.motion.xrel;
            self.mouse_delta_y += event.motion.yrel;
        }
    }

    pub fn isKeyDown(self: Input, scancode: u32) bool {
        return self.keyboard[scancode];
    }
};
