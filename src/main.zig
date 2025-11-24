const std = @import("std");
const App = @import("core/app.zig").App;
const Game = @import("game/game.zig").Game;
const Time = @import("utility/time.zig").Time;

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init();
    defer app.deinit();

    const game = try Game.init(allocator, &app.gfx);
    defer game.deinit(&app.gfx);

    var time = Time.init(null);

    while (app.is_running) {
        time.tick();
        app.pollEvents();
        try game.update(&app.input, time.delta, &app.gfx);
        try game.render(&app.gfx);
        time.limit();
        std.debug.print("FPS: {}\r", .{time.fps});
    }
    return 0;
}
