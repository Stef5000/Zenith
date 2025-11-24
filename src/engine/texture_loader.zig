const std = @import("std");
const c = @import("../c.zig").c;

pub const TextureArrayData = struct {
    width: u32,
    height: u32,
    layer_count: u32,
    pixels: []u8,

    pub fn deinit(self: *TextureArrayData, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }
};

pub fn loadTextures(allocator: std.mem.Allocator, paths: []const []const u8) !TextureArrayData {
    if (paths.len == 0) return error.NoTextures;

    const width: u32 = 16;
    const height: u32 = 16;
    const channels: u32 = 4; // RGBA
    const layer_size = width * height * channels;
    const total_size = layer_size * @as(u32, @intCast(paths.len));
    const final_pixels = try allocator.alloc(u8, total_size);
    errdefer allocator.free(final_pixels);

    for (paths, 0..) |path, i| {
        const file_mode = "rb";
        const rw = c.SDL_IOFromFile(path.ptr, file_mode) orelse {
            std.log.err("Failed to open texture: {s}", .{path});
            return error.FileNotFound;
        };
        const surface = c.SDL_LoadBMP_IO(rw, true) orelse {
            std.log.err("Failed to load BMP: {s}", .{path});
            return error.LoadBMPFailed;
        };
        defer c.SDL_DestroySurface(surface);
        const converted = c.SDL_ConvertSurface(surface, c.SDL_PIXELFORMAT_ABGR8888) orelse return error.ConvertFailed;
        defer c.SDL_DestroySurface(converted);

        if (converted.*.w != width or converted.*.h != height) {
            std.log.err("Texture {s} is not 16x16! Got {}x{}", .{ path, converted.*.w, converted.*.h });
            return error.InvalidSize;
        }
        const src_pixels = @as([*]u8, @ptrCast(converted.*.pixels))[0..layer_size];
        const offset = i * layer_size;
        @memcpy(final_pixels[offset .. offset + layer_size], src_pixels);
    }

    return TextureArrayData{
        .width = width,
        .height = height,
        .layer_count = @as(u32, @intCast(paths.len)),
        .pixels = final_pixels,
    };
}
