const std = @import("std");
const chunk_mod = @import("chunk.zig");
const coord = @import("coord.zig");
const c = @import("../c.zig").c;

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
            return;
        }

        const lx = local_pos.x();
        const ly = local_pos.y();
        const lz = local_pos.z();
        // Check X Neighbors
        if (lx == 0) try self.dirtifyChunk(chunk_pos.x() - 1, chunk_pos.y(), chunk_pos.z());
        if (lx == 31) try self.dirtifyChunk(chunk_pos.x() + 1, chunk_pos.y(), chunk_pos.z());
        // Check Y Neighbors
        if (ly == 0) try self.dirtifyChunk(chunk_pos.x(), chunk_pos.y() - 1, chunk_pos.z());
        if (ly == 31) try self.dirtifyChunk(chunk_pos.x(), chunk_pos.y() + 1, chunk_pos.z());
        // Check Z Neighbors
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
