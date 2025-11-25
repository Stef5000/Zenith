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
const CHUNK_SIZE = 32;
pub const MeshData = std.ArrayList(u32);

pub fn generateMesh(allocator: std.mem.Allocator, world: *const World, chunk_pos: coord.ChunkPos) !MeshData {
    var buffer = MeshData{};
    errdefer buffer.deinit(allocator);
    const chunk = world.getChunk(chunk_pos) orelse return buffer;
    chunk.lock.lockShared();
    defer chunk.lock.unlockShared();
    if (chunk.solid_count == 0) return buffer;
    // Get neighbors for edge culling
    const neighbor_x_pos = world.getChunk(chunk_pos.add(coord.ChunkPos.new(1, 0, 0)));
    const neighbor_x_neg = world.getChunk(chunk_pos.add(coord.ChunkPos.new(-1, 0, 0)));
    const neighbor_y_pos = world.getChunk(chunk_pos.add(coord.ChunkPos.new(0, 1, 0)));
    const neighbor_y_neg = world.getChunk(chunk_pos.add(coord.ChunkPos.new(0, -1, 0)));
    const neighbor_z_pos = world.getChunk(chunk_pos.add(coord.ChunkPos.new(0, 0, 1)));
    const neighbor_z_neg = world.getChunk(chunk_pos.add(coord.ChunkPos.new(0, 0, -1)));
    // PASS 1: X-AXIS (Iterate YZ plane, construct X-rows)
    var y: i32 = 0;
    while (y < CHUNK_SIZE) : (y += 1) {
        var z: i32 = 0;
        while (z < CHUNK_SIZE) : (z += 1) {
            // Construct row mask for X (0..31)
            var row: u32 = 0;
            var x: i32 = 0;
            const base_idx = coord.getLinearIndex(0, y, z);

            while (x < CHUNK_SIZE) : (x += 1) {
                if (chunk.blocks[base_idx + @as(usize, @intCast(x))] != 0) {
                    row |= (@as(u32, 1) << @as(u5, @intCast(x)));
                }
            }
            if (row == 0) continue;
            var faces_right = row & ~(row >> 1);
            // Check Boundary (x=31)
            if ((row & 0x80000000) != 0) {
                var occluded = false;
                if (neighbor_x_pos) |n| {
                    if (n.getBlock(0, y, z) != 0) occluded = true;
                }
                if (occluded) faces_right &= ~(@as(u32, 0x80000000));
            }
            // Face Left (-X) [Index 5] Logic: Solid at i, Air at i-1.
            var faces_left = row & ~(row << 1);
            // Check Boundary (x=0)
            if ((row & 1) != 0) {
                var occluded = false;
                if (neighbor_x_neg) |n| {
                    if (n.getBlock(31, y, z) != 0) occluded = true;
                }
                if (occluded) faces_left &= ~(@as(u32, 1));
            }
            // Generate Vertices for bits
            while (faces_right != 0) {
                const x_idx = @ctz(faces_right);
                const blk = chunk.blocks[base_idx + x_idx];
                try addFace(allocator, &buffer, @intCast(x_idx), y, z, 2, if (blk > 0) blk - 1 else 0);
                faces_right &= faces_right - 1;
            }
            while (faces_left != 0) {
                const x_idx = @ctz(faces_left);
                const blk = chunk.blocks[base_idx + x_idx];
                try addFace(allocator, &buffer, @intCast(x_idx), y, z, 5, if (blk > 0) blk - 1 else 0);
                faces_left &= faces_left - 1;
            }
        }
    }
    // PASS 2: Y-AXIS (Iterate XZ plane, construct Y-columns)
    var x_iter: i32 = 0;
    while (x_iter < CHUNK_SIZE) : (x_iter += 1) {
        var z: i32 = 0;
        while (z < CHUNK_SIZE) : (z += 1) {
            var col: u32 = 0;
            var y_iter: i32 = 0;
            while (y_iter < CHUNK_SIZE) : (y_iter += 1) {
                const idx = coord.getLinearIndex(x_iter, y_iter, z);
                if (chunk.blocks[idx] != 0) {
                    col |= (@as(u32, 1) << @as(u5, @intCast(y_iter)));
                }
            }
            if (col == 0) continue;
            var faces_top = col & ~(col >> 1);
            if ((col & 0x80000000) != 0) {
                var occluded = false;
                if (neighbor_y_pos) |n| {
                    if (n.getBlock(x_iter, 0, z) != 0) occluded = true;
                }
                if (occluded) faces_top &= ~(@as(u32, 0x80000000));
            }
            var faces_bottom = col & ~(col << 1);
            if ((col & 1) != 0) {
                var occluded = false;
                if (neighbor_y_neg) |n| {
                    if (n.getBlock(x_iter, 31, z) != 0) occluded = true;
                }
                if (occluded) faces_bottom &= ~(@as(u32, 1));
            }
            while (faces_top != 0) {
                const y_idx = @ctz(faces_top);
                const idx = coord.getLinearIndex(x_iter, @intCast(y_idx), z);
                const blk = chunk.blocks[idx];
                try addFace(allocator, &buffer, x_iter, @intCast(y_idx), z, 1, if (blk > 0) blk - 1 else 0);
                faces_top &= faces_top - 1;
            }
            while (faces_bottom != 0) {
                const y_idx = @ctz(faces_bottom);
                const idx = coord.getLinearIndex(x_iter, @intCast(y_idx), z);
                const blk = chunk.blocks[idx];
                try addFace(allocator, &buffer, x_iter, @intCast(y_idx), z, 4, if (blk > 0) blk - 1 else 0);
                faces_bottom &= faces_bottom - 1;
            }
        }
    }
    // PASS 3: Z-AXIS (Iterate XY plane, construct Z-rows)
    var x_z: i32 = 0;
    while (x_z < CHUNK_SIZE) : (x_z += 1) {
        var y_z: i32 = 0;
        while (y_z < CHUNK_SIZE) : (y_z += 1) {
            var row: u32 = 0;
            var z_iter: i32 = 0;
            while (z_iter < CHUNK_SIZE) : (z_iter += 1) {
                const idx = coord.getLinearIndex(x_z, y_z, z_iter);
                if (chunk.blocks[idx] != 0) {
                    row |= (@as(u32, 1) << @as(u5, @intCast(z_iter)));
                }
            }
            if (row == 0) continue;
            var faces_front = row & ~(row >> 1);
            if ((row & 0x80000000) != 0) {
                var occluded = false;
                if (neighbor_z_pos) |n| {
                    if (n.getBlock(x_z, y_z, 0) != 0) occluded = true;
                }
                if (occluded) faces_front &= ~(@as(u32, 0x80000000));
            }
            var faces_back = row & ~(row << 1);
            if ((row & 1) != 0) {
                var occluded = false;
                if (neighbor_z_neg) |n| {
                    if (n.getBlock(x_z, y_z, 31) != 0) occluded = true;
                }
                if (occluded) faces_back &= ~(@as(u32, 1));
            }
            while (faces_front != 0) {
                const z_idx = @ctz(faces_front);
                const idx = coord.getLinearIndex(x_z, y_z, @intCast(z_idx));
                const blk = chunk.blocks[idx];
                try addFace(allocator, &buffer, x_z, y_z, @intCast(z_idx), 0, if (blk > 0) blk - 1 else 0);
                faces_front &= faces_front - 1;
            }
            while (faces_back != 0) {
                const z_idx = @ctz(faces_back);
                const idx = coord.getLinearIndex(x_z, y_z, @intCast(z_idx));
                const blk = chunk.blocks[idx];
                try addFace(allocator, &buffer, x_z, y_z, @intCast(z_idx), 3, if (blk > 0) blk - 1 else 0);
                faces_back &= faces_back - 1;
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
        data |= (@as(u32, @intCast(vx)) & 0x3F) << SHIFT_X;
        data |= (@as(u32, @intCast(vy)) & 0x3F) << SHIFT_Y;
        data |= (@as(u32, @intCast(vz)) & 0x3F) << SHIFT_Z;

        data |= (face & 0x7) << SHIFT_FACE;
        data |= (texture_id & 0xFF) << SHIFT_TEX;
        data |= (uv & 0x3) << SHIFT_UV;

        try buffer.append(allocator, data);
    }
}

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
