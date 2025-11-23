const std = @import("std");
const coord = @import("coord.zig");
const chunk_mod = @import("chunk.zig");
const World = @import("world.zig").World;

const SHIFT_X = 0;
const SHIFT_Y = 6;
const SHIFT_Z = 12;
const SHIFT_FACE = 18;
const SHIFT_TEX = 21;
const SHIFT_UV = 29;

// Direction vectors for neighbor checking
const FaceDir = struct { x: i32, y: i32, z: i32 };
const FACES = [6]FaceDir{
    .{ .x = 0, .y = 0, .z = 1 }, // Front (0)
    .{ .x = 0, .y = 1, .z = 0 }, // Top (1)
    .{ .x = 1, .y = 0, .z = 0 }, // Right (2)
    .{ .x = 0, .y = 0, .z = -1 }, // Back (3)
    .{ .x = 0, .y = -1, .z = 0 }, // Bottom (4)
    .{ .x = -1, .y = 0, .z = 0 }, // Left (5)
};

pub const MeshData = std.ArrayList(u32);

pub fn generateMesh(allocator: std.mem.Allocator, world: *const World, chunk_pos: coord.ChunkPos) !MeshData {
    var buffer = MeshData.empty;
    errdefer buffer.deinit(allocator);

    const chunk = world.getChunk(chunk_pos) orelse return buffer;

    var neighbor_chunks: [6]?*chunk_mod.Chunk = undefined;
    inline for (FACES, 0..) |dir, i| {
        const n_pos = chunk_pos.add(coord.ChunkPos.new(dir.x, dir.y, dir.z));
        neighbor_chunks[i] = world.getChunk(n_pos);
    }

    var x: i32 = 0;
    while (x < coord.CHUNK_SIZE) : (x += 1) {
        var y: i32 = 0;
        while (y < coord.CHUNK_SIZE) : (y += 1) {
            var z: i32 = 0;
            while (z < coord.CHUNK_SIZE) : (z += 1) {
                const block_id = chunk.getBlock(x, y, z);
                if (block_id == 0) continue;

                inline for (FACES, 0..) |dir, face_idx| {
                    const nx = x + dir.x;
                    const ny = y + dir.y;
                    const nz = z + dir.z;

                    var is_solid = false;

                    // 1. Check inside current chunk
                    if (nx >= 0 and nx < coord.CHUNK_SIZE and
                        ny >= 0 and ny < coord.CHUNK_SIZE and
                        nz >= 0 and nz < coord.CHUNK_SIZE)
                    {
                        if (chunk.getBlock(nx, ny, nz) != 0) is_solid = true;
                    } else {
                        if (neighbor_chunks[face_idx]) |n_chunk| {
                            const lx = @as(i32, @intCast(@as(u32, @bitCast(nx)) & coord.CHUNK_MASK));
                            const ly = @as(i32, @intCast(@as(u32, @bitCast(ny)) & coord.CHUNK_MASK));
                            const lz = @as(i32, @intCast(@as(u32, @bitCast(nz)) & coord.CHUNK_MASK));

                            if (n_chunk.getBlock(lx, ly, lz) != 0) is_solid = true;
                        } else {
                            is_solid = false;
                        }
                    }
                    if (!is_solid) {
                        try addFace(allocator, &buffer, x, y, z, @intCast(face_idx), block_id);
                    }
                }
            }
        }
    }

    return buffer;
}

fn addFace(allocator: std.mem.Allocator, buffer: *MeshData, x: i32, y: i32, z: i32, face: u32, texture_id: u32) !void {
    const v_pos = [_][3]i32{
        .{ 0, 0, 1 }, .{ 1, 0, 1 }, .{ 1, 1, 1 }, .{ 0, 1, 1 },
        .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 1, 1, 0 }, .{ 0, 1, 0 },
    };

    const indices = switch (face) {
        0 => [_]u32{ 0, 1, 2, 2, 3, 0 },
        1 => [_]u32{ 3, 2, 6, 6, 7, 3 },
        2 => [_]u32{ 1, 5, 6, 6, 2, 1 },
        3 => [_]u32{ 5, 4, 7, 7, 6, 5 },
        4 => [_]u32{ 4, 5, 1, 1, 0, 4 },
        5 => [_]u32{ 4, 0, 3, 3, 7, 4 },
        else => unreachable,
    };

    const uv_ids = [_]u32{ 0, 1, 2, 2, 3, 0 };

    inline for (0..6) |i| {
        const idx = indices[i];
        const vx = x + v_pos[idx][0];
        const vy = y + v_pos[idx][1];
        const vz = z + v_pos[idx][2];
        const uv = uv_ids[i];

        var data: u32 = 0;
        // MASK CHANGED TO 0x3F (63) to allow value '32'
        data |= (@as(u32, @intCast(vx)) & 0x3F) << SHIFT_X;
        data |= (@as(u32, @intCast(vy)) & 0x3F) << SHIFT_Y;
        data |= (@as(u32, @intCast(vz)) & 0x3F) << SHIFT_Z;

        data |= (face & 0x7) << SHIFT_FACE;
        data |= (texture_id & 0xFF) << SHIFT_TEX;
        data |= (uv & 0x3) << SHIFT_UV;

        try buffer.append(allocator, data);
    }
}
