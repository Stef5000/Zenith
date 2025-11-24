const std = @import("std");
const World = @import("../world/world.zig").World;
const coord = @import("../world/coord.zig");
const mesher = @import("../world/mesher.zig");
const SafeQueue = @import("../utility/safe_queue.zig").SafeQueue;
const GfxContext = @import("../engine/gfx.zig").GfxContext;
const c = @import("../c.zig").c;

pub const MeshResult = struct {
    chunk_pos: coord.ChunkPos,
    data: []u32,
};

pub const ChunkManager = struct {
    allocator: std.mem.Allocator,
    pool: std.Thread.Pool,
    results: SafeQueue(MeshResult),
    temp_results: std.ArrayList(MeshResult),

    pub fn init(allocator: std.mem.Allocator) ChunkManager {
        return ChunkManager{
            .allocator = allocator,
            .pool = undefined,
            .results = SafeQueue(MeshResult).init(allocator),
            .temp_results = .{},
        };
    }

    pub fn start(self: *ChunkManager) !void {
        try self.pool.init(.{ .allocator = self.allocator });
    }

    pub fn deinit(self: *ChunkManager) void {
        self.pool.deinit();
        self.results.deinit();
        self.temp_results.deinit(self.allocator);
    }

    pub fn update(self: *ChunkManager, world: *World, gfx: *GfxContext) !void {
        try self.processResults(world, gfx);

        var it = world.chunks.iterator();
        while (it.next()) |entry| {
            const chunk = entry.value_ptr.*;

            // Load acquire to check status
            if (chunk.is_dirty and !chunk.is_meshing.load(.acquire)) {
                chunk.is_meshing.store(true, .release);
                try self.pool.spawn(meshWorker, .{ self, world, entry.key_ptr.* });
            }
        }
    }

    fn processResults(self: *ChunkManager, world: *World, gfx: *GfxContext) !void {
        try self.results.consume(&self.temp_results);

        for (self.temp_results.items) |res| {
            // IMPORTANT: Free the slice we allocated in the worker
            defer self.allocator.free(res.data);

            if (world.getChunk(res.chunk_pos)) |chunk| {
                if (chunk.mesh_buffer) |old| {
                    c.SDL_ReleaseGPUBuffer(gfx.device, old);
                    chunk.mesh_buffer = null;
                }

                if (res.data.len > 0) {
                    // Upload the tight slice
                    chunk.mesh_buffer = try gfx.uploadMesh(res.data);
                    chunk.vertex_count = @intCast(res.data.len);
                } else {
                    chunk.vertex_count = 0;
                }

                chunk.is_dirty = false;
                chunk.is_meshing.store(false, .release);
            }
        }
        self.temp_results.clearRetainingCapacity();
    }
};

fn meshWorker(mgr: *ChunkManager, world: *const World, pos: coord.ChunkPos) void {
    // 1. Create a temporary Arena for this job
    // We use the system allocator (std.heap.page_allocator) or mgr.allocator as backing.
    // Using page_allocator is often better for large temporary arenas to keep heap fragmentation low.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // 2. Generate Mesh using the Arena
    // All ArrayList resizes happen here, lightning fast, no locks.
    const list = mesher.generateMesh(arena_alloc, world, pos) catch |err| {
        std.log.err("Meshing failed: {}", .{err});
        return;
    };

    // 3. Compact and Copy to Main Allocator
    // We allocate EXACTLY what we need on the main heap.
    // This involves ONE lock on the main allocator.
    const final_slice = mgr.allocator.alloc(u32, list.items.len) catch return;
    @memcpy(final_slice, list.items);

    // 4. Push result
    mgr.results.push(MeshResult{
        .chunk_pos = pos,
        .data = final_slice,
    }) catch {
        // If push fails, we must free the main-heap memory we just allocated
        mgr.allocator.free(final_slice);
    };
}
