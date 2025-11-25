const std = @import("std");
const chunk_mod = @import("chunk.zig");
const coord = @import("coord.zig");
const c = @import("../c.zig").c;
const perlin = @import("../math/perlin.zig");

pub const World = struct {
    allocator: std.mem.Allocator,
    chunk_storage: std.SegmentedList(chunk_mod.Chunk, 64),
    chunks: std.AutoHashMap(coord.ChunkPos, *chunk_mod.Chunk),

    pub fn init(allocator: std.mem.Allocator) World {
        return World{
            .allocator = allocator,
            .chunk_storage = .{},
            .chunks = std.AutoHashMap(coord.ChunkPos, *chunk_mod.Chunk).init(allocator),
        };
    }

    pub fn deinit(self: *World, device: *c.SDL_GPUDevice) void {
        var it = self.chunks.valueIterator();
        while (it.next()) |chunk_ptr| {
            chunk_ptr.*.deinit(device);
        }
        self.chunks.deinit();
        self.chunk_storage.deinit(self.allocator);
        perlin.deinit();
    }

    pub fn generateTerrain(self: *World) !void {
        const RADIUS_CHUNKS = 3;
        const SEED = 1337;

        perlin.init(SEED);
        perlin.noiseDetail(4, 0.5);

        var cx: i32 = -RADIUS_CHUNKS;
        while (cx <= RADIUS_CHUNKS) : (cx += 1) {
            var cy: i32 = -2;
            while (cy <= 4) : (cy += 1) {
                var cz: i32 = -RADIUS_CHUNKS;
                while (cz <= RADIUS_CHUNKS) : (cz += 1) {
                    const chunk_pos = coord.ChunkPos.new(cx, cy, cz);
                    const chunk = try self.createChunk(chunk_pos);
                    // OPTIMIZATION: Local counters to avoid atomic/lock overhead per block
                    var local_solid_count: u16 = 0;
                    // We write directly to the array.
                    // Safe because is_dirty is false, so Mesher ignores this chunk.
                    var lx: i32 = 0;
                    while (lx < 32) : (lx += 1) {
                        var lz: i32 = 0;
                        while (lz < 32) : (lz += 1) {
                            const wx = cx * 32 + lx;
                            const wz = cz * 32 + lz;

                            const scale = 0.02;
                            const noise = perlin.noise2(@as(f32, @floatFromInt(wx)) * scale, @as(f32, @floatFromInt(wz)) * scale);
                            const height = @as(i32, @intFromFloat(32.0 + noise * 64.0));

                            var ly: i32 = 0;
                            while (ly < 32) : (ly += 1) {
                                const wy = cy * 32 + ly;

                                if (wy <= height) {
                                    var block: u8 = 0;
                                    if (wy == height) block = 3 else if (wy > height - 4) block = 1 else block = 2;

                                    // Direct Array Access (Fast)
                                    const index = coord.getLinearIndex(lx, ly, lz);
                                    chunk.blocks[index] = block;
                                    local_solid_count += 1;
                                }
                            }
                        }
                    }
                    chunk.solid_count = local_solid_count;
                    chunk.is_dirty = true;
                }
            }
        }
        std.log.info("Terrain Generation Complete. Chunks: {}", .{self.chunks.count()});
    }

    pub fn getChunk(self: *const World, chunk_pos: coord.ChunkPos) ?*chunk_mod.Chunk {
        return self.chunks.get(chunk_pos);
    }

    pub fn createChunk(self: *World, chunk_pos: coord.ChunkPos) !*chunk_mod.Chunk {
        if (self.chunks.get(chunk_pos)) |existing| {
            return existing;
        }
        const ptr = try self.chunk_storage.addOne(self.allocator);
        ptr.* = chunk_mod.Chunk.init();
        try self.chunks.put(chunk_pos, ptr);
        return ptr;
    }

    pub fn setBlock(self: *World, x: i32, y: i32, z: i32, block: u8) !void {
        const global_pos = coord.BlockPos.new(x, y, z);
        const chunk_pos = coord.worldToChunk(global_pos);
        const local_pos = coord.worldToLocal(global_pos);

        if (self.getChunk(chunk_pos)) |chunk| {
            chunk.setBlock(local_pos.x(), local_pos.y(), local_pos.z(), block);
        } else {
            const new_chunk = try self.createChunk(chunk_pos);
            new_chunk.setBlock(local_pos.x(), local_pos.y(), local_pos.z(), block);
        }

        const lx = local_pos.x();
        const ly = local_pos.y();
        const lz = local_pos.z();

        if (lx == 0) try self.dirtifyChunk(chunk_pos.x() - 1, chunk_pos.y(), chunk_pos.z());
        if (lx == 31) try self.dirtifyChunk(chunk_pos.x() + 1, chunk_pos.y(), chunk_pos.z());
        if (ly == 0) try self.dirtifyChunk(chunk_pos.x(), chunk_pos.y() - 1, chunk_pos.z());
        if (ly == 31) try self.dirtifyChunk(chunk_pos.x(), chunk_pos.y() + 1, chunk_pos.z());
        if (lz == 0) try self.dirtifyChunk(chunk_pos.x(), chunk_pos.y(), chunk_pos.z() - 1);
        if (lz == 31) try self.dirtifyChunk(chunk_pos.x(), chunk_pos.y(), chunk_pos.z() + 1);
    }

    fn dirtifyChunk(self: *World, cx: i32, cy: i32, cz: i32) !void {
        const pos = coord.ChunkPos.new(cx, cy, cz);
        if (self.getChunk(pos)) |chunk| {
            chunk.is_dirty = true;
        }
    }
};
