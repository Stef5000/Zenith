const std = @import("std");
const coord = @import("coord.zig");
const c = @import("../c.zig").c;

pub const BlockID = u8;

pub const Chunk = struct {
    lock: std.Thread.RwLock,
    is_meshing: std.atomic.Value(bool),

    is_dirty: bool,
    is_modified: bool,

    blocks: [coord.CHUNK_VOLUME]BlockID align(64),
    solid_count: u16,

    mesh_buffer: ?*c.SDL_GPUBuffer,
    vertex_count: u32,

    pub fn init() Chunk {
        return Chunk{
            .lock = .{},
            .is_meshing = std.atomic.Value(bool).init(false),
            .is_dirty = true,
            .is_modified = false,
            .blocks = @splat(0),
            .solid_count = 0,
            .mesh_buffer = null,
            .vertex_count = 0,
        };
    }

    pub fn deinit(self: *Chunk, device: *c.SDL_GPUDevice) void {
        if (self.mesh_buffer) |buf| {
            c.SDL_ReleaseGPUBuffer(device, buf);
            self.mesh_buffer = null;
        }
    }

    pub inline fn getBlock(self: *const Chunk, x: i32, y: i32, z: i32) BlockID {
        const index = coord.getLinearIndex(x, y, z);
        return self.blocks[index];
    }

    pub fn setBlock(self: *Chunk, x: i32, y: i32, z: i32, block: BlockID) void {
        const index = coord.getLinearIndex(x, y, z);

        self.lock.lock();
        defer self.lock.unlock();

        const old_block = self.blocks[index];
        if (old_block == block) return;
        if (old_block == 0 and block != 0) {
            self.solid_count += 1;
        } else if (old_block != 0 and block == 0) {
            self.solid_count -= 1;
        }
        self.blocks[index] = block;
        self.is_dirty = true;
        self.is_modified = true;
    }

    pub fn fill(self: *Chunk, block: BlockID) void {
        self.lock.lock();
        defer self.lock.unlock();
        @memset(&self.blocks, block);
        if (block == 0) {
            self.solid_count = 0;
        } else {
            self.solid_count = coord.CHUNK_VOLUME;
        }

        self.is_dirty = true;
        self.is_modified = true;
    }
};
