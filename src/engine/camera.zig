const std = @import("std");
const math = @import("../math/math.zig");
const Input = @import("input.zig").Input;
const c = @import("../c.zig").c;

const YAW_DEFAULT: f32 = -90.0;
const PITCH_DEFAULT: f32 = 0.0;
const SPEED_DEFAULT: f32 = 5.0;
const SENSITIVITY: f32 = 0.05;

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
            .yaw = YAW_DEFAULT,
            .pitch = PITCH_DEFAULT,
        };
        cam.updateVectors();
        return cam;
    }

    pub fn getViewMatrix(self: Camera) math.Mat4 {
        const target = self.position.add(self.front);
        return math.Mat4.lookAt(self.position, target, self.up);
    }

    pub fn update(self: *Camera, input: *Input, dt: f32) void {
        const x_offset = input.mouse_delta_x * SENSITIVITY;
        const y_offset = input.mouse_delta_y * SENSITIVITY;
        self.yaw += x_offset;
        self.pitch -= y_offset;

        if (self.pitch > 85.0) self.pitch = 85.0;
        if (self.pitch < -85.0) self.pitch = -85.0;
        self.updateVectors();
        const velocity = SPEED_DEFAULT * dt;

        if (input.isKeyDown(c.SDL_SCANCODE_W)) self.position = self.position.add(self.front.scale(velocity));
        if (input.isKeyDown(c.SDL_SCANCODE_S)) self.position = self.position.sub(self.front.scale(velocity));
        if (input.isKeyDown(c.SDL_SCANCODE_A)) self.position = self.position.sub(self.right.scale(velocity));
        if (input.isKeyDown(c.SDL_SCANCODE_D)) self.position = self.position.add(self.right.scale(velocity));
        if (input.isKeyDown(c.SDL_SCANCODE_SPACE)) self.position = self.position.add(self.world_up.scale(velocity));
        if (input.isKeyDown(c.SDL_SCANCODE_LCTRL)) self.position = self.position.sub(self.world_up.scale(velocity));
    }

    fn updateVectors(self: *Camera) void {
        // Calculate the new Front vector
        var new_front = math.Vec3.new(
            @cos(math.toRadians(self.yaw)) * @cos(math.toRadians(self.pitch)),
            @sin(math.toRadians(self.pitch)),
            @sin(math.toRadians(self.yaw)) * @cos(math.toRadians(self.pitch)),
        );

        self.front = new_front.norm();

        // Recalculate Right and Up vectors
        // Normalize the vectors, because their length gets closer to 0 the more you look up or down which results in slower movement.
        self.right = self.front.cross(self.world_up).norm();
        self.up = self.right.cross(self.front).norm();
    }
};
