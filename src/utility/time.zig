const c = @import("../c.zig").c;

pub const Time = struct {
    last_counter: u64,
    frequency: f64,
    delta: f32,

    pub fn init() Time {
        return Time{
            .last_counter = c.SDL_GetPerformanceCounter(),
            .frequency = @floatFromInt(c.SDL_GetPerformanceFrequency()),
            .delta = 0.0,
        };
    }

    pub fn tick(self: *Time) void {
        const now = c.SDL_GetPerformanceCounter();
        const diff = now - self.last_counter;
        self.last_counter = now;
        self.delta = @as(f32, @floatFromInt(diff)) / @as(f32, @floatCast(self.frequency));
    }
};
