const std = @import("std");
const math = @import("math.zig");
const World = @import("../world/world.zig").World;
const coord = @import("../world/coord.zig");

pub const RayHit = struct {
    block_pos: coord.BlockPos,
    face_normal: coord.BlockPos,
    active: bool,
};

pub fn raycast(world: *const World, origin: math.Vec3, dir: math.Vec3, max_dist: f32) RayHit {
    var x = @as(i32, @intFromFloat(@floor(origin.x())));
    var y = @as(i32, @intFromFloat(@floor(origin.y())));
    var z = @as(i32, @intFromFloat(@floor(origin.z())));

    const step_x: i32 = if (dir.x() > 0) 1 else -1;
    const step_y: i32 = if (dir.y() > 0) 1 else -1;
    const step_z: i32 = if (dir.z() > 0) 1 else -1;

    const t_delta_x = if (dir.x() != 0) @abs(1.0 / dir.x()) else std.math.floatMax(f32);
    const t_delta_y = if (dir.y() != 0) @abs(1.0 / dir.y()) else std.math.floatMax(f32);
    const t_delta_z = if (dir.z() != 0) @abs(1.0 / dir.z()) else std.math.floatMax(f32);

    const frac_x = origin.x() - @floor(origin.x());
    const frac_y = origin.y() - @floor(origin.y());
    const frac_z = origin.z() - @floor(origin.z());

    var t_max_x = if (step_x > 0) (1.0 - frac_x) * t_delta_x else frac_x * t_delta_x;
    var t_max_y = if (step_y > 0) (1.0 - frac_y) * t_delta_y else frac_y * t_delta_y;
    var t_max_z = if (step_z > 0) (1.0 - frac_z) * t_delta_z else frac_z * t_delta_z;

    var normal = coord.BlockPos.new(0, 0, 0);

    while (true) {
        const chunk_pos = coord.worldToChunk(coord.BlockPos.new(x, y, z));
        const local_pos = coord.worldToLocal(coord.BlockPos.new(x, y, z));

        if (world.getChunk(chunk_pos)) |chunk| {
            const block = chunk.getBlock(local_pos.x(), local_pos.y(), local_pos.z());
            if (block != 0) {
                return RayHit{
                    .block_pos = coord.BlockPos.new(x, y, z),
                    .face_normal = normal,
                    .active = true,
                };
            }
        }
        if (t_max_x < t_max_y) {
            if (t_max_x < t_max_z) {
                if (t_max_x > max_dist) break;
                x += step_x;
                t_max_x += t_delta_x;
                normal = coord.BlockPos.new(-step_x, 0, 0);
            } else {
                if (t_max_z > max_dist) break;
                z += step_z;
                t_max_z += t_delta_z;
                normal = coord.BlockPos.new(0, 0, -step_z);
            }
        } else {
            if (t_max_y < t_max_z) {
                if (t_max_y > max_dist) break;
                y += step_y;
                t_max_y += t_delta_y;
                normal = coord.BlockPos.new(0, -step_y, 0);
            } else {
                if (t_max_z > max_dist) break;
                z += step_z;
                t_max_z += t_delta_z;
                normal = coord.BlockPos.new(0, 0, -step_z);
            }
        }
    }

    return RayHit{
        .block_pos = coord.BlockPos.zero(),
        .face_normal = coord.BlockPos.zero(),
        .active = false,
    };
}
