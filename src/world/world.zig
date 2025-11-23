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
            const new_chunk = try self.createChunk(chunk_pos);
            new_chunk.setBlock(local_pos.x(), local_pos.y(), local_pos.z(), block);
        }
    }
};
