const std = @import("std");
const math = @import("../math/math.zig");
const c = @import("../c.zig").c;
const mesher = @import("../world/mesher.zig");
const tex_loader = @import("../engine/texture_loader.zig");
const raycast = @import("../math/raycast.zig");
const GfxContext = @import("../engine/gfx.zig").GfxContext;
const Input = @import("../engine/input.zig").Input;
const Camera = @import("../engine/camera.zig").Camera;
const World = @import("../world/world.zig").World;
const ChunkManager = @import("chunk_manager.zig").ChunkManager;
const Player = @import("player.zig").Player;

pub const Game = struct {
    allocator: std.mem.Allocator,
    player: Player,
    world: World,
    chunk_manager: ChunkManager,
    mouse_cooldown: f32 = 0.0,
    selected_block: u8 = 1,

    pub fn init(allocator: std.mem.Allocator, gfx: *GfxContext) !*Game {
        const self = try allocator.create(Game);
        self.allocator = allocator;
        self.player = Player.init(math.Vec3.new(0, 100, 0));
        self.player.camera.pitch = -45.0;
        self.world = World.init(allocator);
        self.chunk_manager = ChunkManager.init(allocator);
        try self.chunk_manager.start();
        const paths = [_][]const u8{ "assets/block_textures/dirt.bmp", "assets/block_textures/stone.bmp", "assets/block_textures/gras.bmp" };
        const tex_data = try tex_loader.loadTextures(allocator, &paths);
        try gfx.createTextureArray(tex_data);
        var mut_data = tex_data;
        mut_data.deinit(allocator);
        try self.world.generateTerrain();
        return self;
    }

    pub fn deinit(self: *Game, gfx: *GfxContext) void {
        self.chunk_manager.deinit();
        self.world.deinit(gfx.device);
        self.allocator.destroy(self);
    }

    pub fn update(self: *Game, input: *Input, dt: f32, gfx: *GfxContext) !void {
        self.player.update(dt, input, &self.world);

        if (input.isKeyDown(c.SDL_SCANCODE_1)) self.selected_block = 1; // Stone
        if (input.isKeyDown(c.SDL_SCANCODE_2)) self.selected_block = 2; // Grass
        if (input.isKeyDown(c.SDL_SCANCODE_3)) self.selected_block = 3; // Dirt

        if (self.mouse_cooldown > 0) {
            self.mouse_cooldown -= dt;
        } else {
            const left_click = input.isMouseButtonDown(1);
            const right_click = input.isMouseButtonDown(3);

            if (left_click or right_click) {
                const hit = raycast.raycast(&self.world, self.player.camera.position, self.player.camera.front, 5.0);
                if (hit.active) {
                    if (left_click) {
                        try self.world.setBlock(hit.block_pos.x(), hit.block_pos.y(), hit.block_pos.z(), 0);
                        self.mouse_cooldown = 0.2;
                    } else if (right_click) {
                        const place_pos = hit.block_pos.add(hit.face_normal);
                        if (!self.player.intersectsBlock(place_pos.x(), place_pos.y(), place_pos.z())) {
                            try self.world.setBlock(place_pos.x(), place_pos.y(), place_pos.z(), self.selected_block);
                            self.mouse_cooldown = 0.2;
                        }
                    }
                }
            }
        }
        try self.chunk_manager.update(&self.world, gfx);
    }

    pub fn render(self: *Game, gfx: *GfxContext) !void {
        const proj = math.Mat4.perspective(60.0, 16.0 / 9.0, 0.1, 1000.0);
        const view = self.player.camera.getViewMatrix();
        const view_proj = proj.mul(view);

        try gfx.renderChunks(view_proj, &self.world);
    }
};
