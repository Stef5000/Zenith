const std = @import("std");
const math = @import("../math/math.zig");

pub const CHUNK_SIZE_LOG2 = 5;
pub const CHUNK_SIZE = 32;
pub const CHUNK_MASK = 31;
pub const CHUNK_VOLUME = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE;

pub const BlockPos = math.Vec3_i32;
pub const ChunkPos = math.Vec3_i32;

pub fn worldToChunk(pos: BlockPos) ChunkPos {
    return ChunkPos.new(
        pos.x() >> CHUNK_SIZE_LOG2,
        pos.y() >> CHUNK_SIZE_LOG2,
        pos.z() >> CHUNK_SIZE_LOG2,
    );
}

pub fn worldToLocal(pos: BlockPos) BlockPos {
    return BlockPos.new(
        pos.x() & CHUNK_MASK,
        pos.y() & CHUNK_MASK,
        pos.z() & CHUNK_MASK,
    );
}

pub inline fn getLinearIndex(x: i32, y: i32, z: i32) usize {
    const ux = @as(usize, @intCast(x));
    const uy = @as(usize, @intCast(y));
    const uz = @as(usize, @intCast(z));
    return (uy << (CHUNK_SIZE_LOG2 * 2)) | (uz << CHUNK_SIZE_LOG2) | ux;
}
