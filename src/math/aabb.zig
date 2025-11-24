const std = @import("std");
const math = @import("math.zig");

pub const AABB = struct {
    min: math.Vec3,
    max: math.Vec3,

    pub fn fromPosition(pos: math.Vec3, width: f32, height: f32) AABB {
        const half_w = width / 2.0;
        return AABB{
            .min = math.Vec3.new(pos.x() - half_w, pos.y(), pos.z() - half_w),
            .max = math.Vec3.new(pos.x() + half_w, pos.y() + height, pos.z() + half_w),
        };
    }
};

pub fn checkOverlap(a: AABB, b: AABB) bool {
    return (a.min.x() < b.max.x() and a.max.x() > b.min.x() and
        a.min.y() < b.max.y() and a.max.y() > b.min.y() and
        a.min.z() < b.max.z() and a.max.z() > b.min.z());
}
