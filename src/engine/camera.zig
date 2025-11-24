const std = @import("std");
const math = @import("../math/math.zig");

pub const Camera = struct {
    position: math.Vec3,
    front: math.Vec3,
    up: math.Vec3,
    right: math.Vec3,
    world_up: math.Vec3,

    yaw: f32,
    pitch: f32,

    pub fn init(position: math.Vec3) Camera {
        var cam = Camera{
            .position = position,
            .world_up = math.Vec3.new(0, 1, 0),
            .front = math.Vec3.new(0, 0, -1),
            .up = math.Vec3.new(0, 1, 0),
            .right = math.Vec3.new(1, 0, 0),
            .yaw = -90.0,
            .pitch = 0.0,
        };
        cam.updateVectors();
        return cam;
    }

    pub fn getViewMatrix(self: Camera) math.Mat4 {
        const target = self.position.add(self.front);
        return math.Mat4.lookAt(self.position, target, self.up);
    }

    pub fn handleMouse(self: *Camera, dx: f32, dy: f32) void {
        const sensitivity = 0.04;
        self.yaw += dx * sensitivity;
        self.pitch -= dy * sensitivity;

        if (self.pitch > 89.0) self.pitch = 89.0;
        if (self.pitch < -89.0) self.pitch = -89.0;

        self.updateVectors();
    }

    fn updateVectors(self: *Camera) void {
        const rad_yaw = math.toRadians(self.yaw);
        const rad_pitch = math.toRadians(self.pitch);

        var new_front = math.Vec3.new(
            @cos(rad_yaw) * @cos(rad_pitch),
            @sin(rad_pitch),
            @sin(rad_yaw) * @cos(rad_pitch),
        );
        self.front = new_front.norm();
        self.right = self.front.cross(self.world_up).norm();
        self.up = self.right.cross(self.front).norm();
    }
};
