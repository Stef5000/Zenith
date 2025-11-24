const std = @import("std");
const math = @import("../math/math.zig");
const Camera = @import("../engine/camera.zig").Camera;
const World = @import("../world/world.zig").World;
const Input = @import("../engine/input.zig").Input;
const c = @import("../c.zig").c;
const AABB = @import("../math/aabb.zig").AABB;
const aabb_utils = @import("../math/aabb.zig");

const GRAVITY: f32 = 28.0;
const JUMP_FORCE: f32 = 9.0;
const WALK_SPEED: f32 = 6.0;
const FLY_SPEED: f32 = 15.0;
const FRICTION: f32 = 10.0;
const PLAYER_WIDTH: f32 = 0.6;
const PLAYER_HEIGHT: f32 = 1.8;
const EYE_HEIGHT: f32 = 1.6;

pub const PlayerMode = enum { Walking, Flying };

pub const Player = struct {
    camera: Camera,
    position: math.Vec3,
    velocity: math.Vec3,

    mode: PlayerMode,
    on_ground: bool,

    pub fn init(start_pos: math.Vec3) Player {
        return Player{
            .camera = Camera.init(start_pos.add(math.Vec3.new(0, EYE_HEIGHT, 0))),
            .position = start_pos,
            .velocity = math.Vec3.zero(),
            .mode = .Flying,
            .on_ground = false,
        };
    }

    pub fn update(self: *Player, dt: f32, input: *Input, world: *const World) void {
        if (input.isKeyDown(c.SDL_SCANCODE_F)) {
            self.mode = if (self.mode == .Walking) .Flying else .Walking;
            self.velocity = math.Vec3.zero();
        }

        self.camera.handleMouse(input.mouse_delta_x, input.mouse_delta_y);

        if (self.mode == .Flying) {
            self.updateFlying(dt, input);
        } else {
            self.updateWalking(dt, input, world);
        }

        const eye_pos = self.position.add(math.Vec3.new(0, EYE_HEIGHT, 0));
        self.camera.position = eye_pos;
    }

    fn updateFlying(self: *Player, dt: f32, input: *Input) void {
        var vel = math.Vec3.zero();
        const cam_front = self.camera.front;
        const cam_right = self.camera.right;

        if (input.isKeyDown(c.SDL_SCANCODE_W)) vel = vel.add(cam_front);
        if (input.isKeyDown(c.SDL_SCANCODE_S)) vel = vel.sub(cam_front);
        if (input.isKeyDown(c.SDL_SCANCODE_A)) vel = vel.sub(cam_right);
        if (input.isKeyDown(c.SDL_SCANCODE_D)) vel = vel.add(cam_right);
        if (input.isKeyDown(c.SDL_SCANCODE_SPACE)) vel = vel.add(math.Vec3.new(0, 1, 0));
        if (input.isKeyDown(c.SDL_SCANCODE_LCTRL)) vel = vel.sub(math.Vec3.new(0, 1, 0));
        if (vel.lengthSq() > 0) vel = vel.norm();
        self.position = self.position.add(vel.scale(FLY_SPEED * dt));
    }

    fn updateWalking(self: *Player, dt: f32, input: *Input, world: *const World) void {
        const flat_front = math.Vec3.new(self.camera.front.x(), 0, self.camera.front.z()).norm();
        const flat_right = self.camera.right;

        var input_dir = math.Vec3.zero();
        if (input.isKeyDown(c.SDL_SCANCODE_W)) input_dir = input_dir.add(flat_front);
        if (input.isKeyDown(c.SDL_SCANCODE_S)) input_dir = input_dir.sub(flat_front);
        if (input.isKeyDown(c.SDL_SCANCODE_A)) input_dir = input_dir.sub(flat_right);
        if (input.isKeyDown(c.SDL_SCANCODE_D)) input_dir = input_dir.add(flat_right);

        if (input_dir.lengthSq() > 0) input_dir = input_dir.norm();
        self.velocity.data[0] = input_dir.x() * WALK_SPEED;
        self.velocity.data[2] = input_dir.z() * WALK_SPEED;
        self.velocity.data[1] -= GRAVITY * dt;

        if (self.on_ground and input.isKeyDown(c.SDL_SCANCODE_SPACE)) {
            self.velocity.data[1] = JUMP_FORCE;
            self.on_ground = false;
        }

        self.on_ground = false;
        self.position.data[0] += self.velocity.x() * dt;
        if (self.checkCollision(world)) {
            self.position.data[0] -= self.velocity.x() * dt;
            self.velocity.data[0] = 0;
        }

        self.position.data[2] += self.velocity.z() * dt;
        if (self.checkCollision(world)) {
            self.position.data[2] -= self.velocity.z() * dt;
            self.velocity.data[2] = 0;
        }

        self.position.data[1] += self.velocity.y() * dt;
        if (self.checkCollision(world)) {
            self.position.data[1] -= self.velocity.y() * dt;

            if (self.velocity.y() < 0) {
                self.on_ground = true;
            }
            self.velocity.data[1] = 0;
        }

        if (self.velocity.y() < -50.0) self.velocity.data[1] = -50.0;
    }

    fn checkCollision(self: Player, world: *const World) bool {
        const box = AABB.fromPosition(self.position, PLAYER_WIDTH, PLAYER_HEIGHT);
        const min_x = @as(i32, @intFromFloat(@floor(box.min.x())));
        const max_x = @as(i32, @intFromFloat(@floor(box.max.x())));
        const min_y = @as(i32, @intFromFloat(@floor(box.min.y())));
        const max_y = @as(i32, @intFromFloat(@floor(box.max.y())));
        const min_z = @as(i32, @intFromFloat(@floor(box.min.z())));
        const max_z = @as(i32, @intFromFloat(@floor(box.max.z())));

        var x = min_x;
        while (x <= max_x) : (x += 1) {
            var y = min_y;
            while (y <= max_y) : (y += 1) {
                var z = min_z;
                while (z <= max_z) : (z += 1) {
                    if (isSolid(world, x, y, z)) {
                        return true;
                    }
                }
            }
        }

        return false;
    }

    pub fn getAABB(self: Player) AABB {
        return AABB.fromPosition(self.position, PLAYER_WIDTH, PLAYER_HEIGHT);
    }

    pub fn intersectsBlock(self: Player, bx: i32, by: i32, bz: i32) bool {
        const player_box = self.getAABB();

        const fx = @as(f32, @floatFromInt(bx));
        const fy = @as(f32, @floatFromInt(by));
        const fz = @as(f32, @floatFromInt(bz));

        const block_box = AABB{
            .min = math.Vec3.new(fx, fy, fz),
            .max = math.Vec3.new(fx + 1.0, fy + 1.0, fz + 1.0),
        };

        return aabb_utils.checkOverlap(player_box, block_box);
    }

    fn isSolid(world: *const World, x: i32, y: i32, z: i32) bool {
        const coords = @import("../world/coord.zig");
        const global_pos = coords.BlockPos.new(x, y, z);
        const chunk_pos = coords.worldToChunk(global_pos);
        const local_pos = coords.worldToLocal(global_pos);

        if (world.getChunk(chunk_pos)) |chunk| {
            const block = chunk.getBlock(local_pos.x(), local_pos.y(), local_pos.z());
            return block != 0;
        }
        return false;
    }
};
