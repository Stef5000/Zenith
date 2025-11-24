const std = @import("std");
const c = @import("../c.zig").c;

pub const Time = struct {
    last_counter: u64,
    frequency: u64,
    delta: f32,

    fps: u32,
    frame_counter: u32,
    time_accumulator: f32,

    target_fps: ?u32, // null = unlimited

    pub fn init(target_fps: ?u32) Time {
        return Time{
            .last_counter = c.SDL_GetPerformanceCounter(),
            .frequency = c.SDL_GetPerformanceFrequency(),
            .delta = 0.0,
            .fps = 0,
            .frame_counter = 0,
            .time_accumulator = 0.0,
            .target_fps = target_fps,
        };
    }

    pub fn tick(self: *Time) void {
        const now = c.SDL_GetPerformanceCounter();
        const diff = now - self.last_counter;
        self.last_counter = now;
        self.delta = @as(f32, @floatFromInt(diff)) / @as(f32, @floatFromInt(self.frequency));
        if (self.delta > 0.1) self.delta = 0.1;
        self.time_accumulator += self.delta;
        self.frame_counter += 1;
        if (self.time_accumulator >= 1.0) {
            self.fps = self.frame_counter;
            self.frame_counter = 0;
            self.time_accumulator -= 1.0;
        }
    }

    pub fn limit(self: *Time) void {
        if (self.target_fps) |target| {
            const now = c.SDL_GetPerformanceCounter();
            const elapsed = now - self.last_counter;
            const target_duration = self.frequency / target;

            if (elapsed < target_duration) {
                const remaining_counts = target_duration - elapsed;
                const ns = (remaining_counts * 1_000_000_000) / self.frequency;
                c.SDL_DelayNS(ns);
            }
        }
    }
};
