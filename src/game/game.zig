const std = @import("std");
const math = @import("../math/math.zig");
const GfxContext = @import("../engine/gfx.zig").GfxContext;
const Input = @import("../engine/input.zig").Input;
const Camera = @import("../engine/camera.zig").Camera;
const World = @import("../world/world.zig").World;
const mesher = @import("../world/mesher.zig");

pub const Game = struct {
    allocator: std.mem.Allocator,
    camera: Camera,
    world: World,

    pub fn init(allocator: std.mem.Allocator) !*Game {
        const self = try allocator.create(Game);
        self.allocator = allocator;
        self.camera = Camera.init(math.Vec3.new(0, 40, 40)); // Start high up looking down
        self.camera.pitch = -45.0;
        self.world = World.init(allocator);

        const RADIUS = 1;
        var cx: i32 = -RADIUS;
        while (cx <= RADIUS) : (cx += 1) {
            var cy: i32 = -RADIUS;
            while (cy <= RADIUS) : (cy += 1) {
                var cz: i32 = -RADIUS;
                while (cz <= RADIUS) : (cz += 1) {
                    const cpos = math.Vec3_i32.new(cx, cy, cz);
                    const chunk = try self.world.createChunk(cpos);

                    // Fill with simple terrain pattern
                    var bx: i32 = 0;
                    while (bx < 32) : (bx += 1) {
                        var bz: i32 = 0;
                        while (bz < 32) : (bz += 1) {
                            // Simple sine wave terrain
                            const fx = @as(f32, @floatFromInt(cx * 32 + bx));
                            const fz = @as(f32, @floatFromInt(cz * 32 + bz));
                            const height = @as(i32, @intFromFloat(16.0 + 10.0 * @sin(fx * 0.1) * @cos(fz * 0.1)));

                            var by: i32 = 0;
                            while (by < 32) : (by += 1) {
                                const world_y = cy * 32 + by;
                                if (world_y < height) {
                                    chunk.setBlock(bx, by, bz, 2); // Stone
                                } else if (world_y == height) {
                                    chunk.setBlock(bx, by, bz, 2); // Grass
                                }
                            }
                        }
                    }
                }
            }
        }
        std.log.info("Generated World with {} chunks", .{self.world.chunks.count()});

        return self;
    }

    pub fn deinit(self: *Game, gfx: *GfxContext) void {
        self.world.deinit(gfx.device);
        self.allocator.destroy(self);
    }

    pub fn update(self: *Game, input: *Input, dt: f32, gfx: *GfxContext) !void {
        self.camera.update(input, dt);

        // --- Mesh Updates ---
        // Simple synchronous meshing for now.
        // Iterate all chunks, if dirty, rebuild mesh.
        var it = self.world.chunks.iterator();
        while (it.next()) |entry| {
            const chunk_pos = entry.key_ptr.*;
            const chunk = entry.value_ptr.*;

            if (chunk.is_dirty) {
                var mesh_data = try mesher.generateMesh(self.allocator, &self.world, chunk_pos);
                defer mesh_data.deinit(self.allocator);

                // 2. Release old GPU buffer if exists
                if (chunk.mesh_buffer) |old_buf| {
                    @import("../c.zig").c.SDL_ReleaseGPUBuffer(gfx.device, old_buf);
                    chunk.mesh_buffer = null;
                }

                // 3. Upload new buffer
                if (mesh_data.items.len > 0) {
                    chunk.mesh_buffer = try gfx.uploadMesh(mesh_data.items);
                    chunk.vertex_count = @intCast(mesh_data.items.len);
                } else {
                    chunk.vertex_count = 0;
                }

                chunk.is_dirty = false;
            }
        }
    }

    pub fn render(self: *Game, gfx: *GfxContext) !void {
        const proj = math.Mat4.perspective(60.0, 1280.0 / 720.0, 0.1, 1000.0);
        const view = self.camera.getViewMatrix();
        const view_proj = proj.mul(view);

        try gfx.renderChunks(view_proj, &self.world);
    }
};
