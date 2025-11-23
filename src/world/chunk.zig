const std = @import("std");
const coord = @import("coord.zig");
const c = @import("../c.zig").c;

// ID Types
pub const BlockID = u8;

pub const Chunk = struct {
    // State
    is_dirty: bool,
    is_modified: bool,

    // Data (32KB)
    blocks: [coord.CHUNK_VOLUME]BlockID align(64),

    // GPU Resources
    mesh_buffer: ?*c.SDL_GPUBuffer,
    vertex_count: u32,

    pub fn init() Chunk {
        return Chunk{
            .is_dirty = true,
            .is_modified = false,
            .blocks = @splat(0),
            .mesh_buffer = null,
            .vertex_count = 0,
        };
    }

    /// Releases the GPU Buffer associated with this chunk
    pub fn deinit(self: *Chunk, device: *c.SDL_GPUDevice) void {
        if (self.mesh_buffer) |buf| {
            c.SDL_ReleaseGPUBuffer(device, buf);
            self.mesh_buffer = null;
        }
    }

    // ... (Keep getBlock, setBlock, fill) ...
    pub inline fn getBlock(self: *const Chunk, x: i32, y: i32, z: i32) BlockID {
        const index = coord.getLinearIndex(x, y, z);
        return self.blocks[index];
    }

    pub inline fn setBlock(self: *Chunk, x: i32, y: i32, z: i32, block: BlockID) void {
        const index = coord.getLinearIndex(x, y, z);
        if (self.blocks[index] == block) return;

        self.blocks[index] = block;
        self.is_dirty = true;
        self.is_modified = true;
    }

    pub fn fill(self: *Chunk, block: BlockID) void {
        @memset(&self.blocks, block);
        self.is_dirty = true;
        self.is_modified = true;
    }
};
