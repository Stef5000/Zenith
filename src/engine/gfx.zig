const std = @import("std");
const c = @import("../c.zig").c;
const math = @import("../math/math.zig");
const World = @import("../world/world.zig").World;
const coord = @import("../world/coord.zig");

pub const GfxContext = struct {
    device: *c.SDL_GPUDevice,
    window: *c.SDL_Window,

    // Pipelines
    chunk_pipeline: *c.SDL_GPUGraphicsPipeline,

    // Resources
    depth_texture: ?*c.SDL_GPUTexture,

    // Window State
    width: u32,
    height: u32,

    pub fn init(window: *c.SDL_Window) !GfxContext {
        // 1. Initialize Device
        const device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, true, // Debug Mode
            null) orelse return error.GpuInitFailed;
        errdefer c.SDL_DestroyGPUDevice(device);

        if (!c.SDL_ClaimWindowForGPUDevice(device, window)) {
            return error.WindowClaimFailed;
        }

        // 2. Load Shaders
        // Vertex: 2 Uniform Slots (0: MVP, 1: ChunkPos), 0 Samplers
        const chunk_vert = try loadShader(device, "src/shaders/chunk.vert.spv", 2, 0);
        // Fragment: 0 Uniforms, 0 Samplers (We aren't using textures yet)
        const chunk_frag = try loadShader(device, "src/shaders/chunk.frag.spv", 0, 0);

        defer c.SDL_ReleaseGPUShader(device, chunk_vert);
        defer c.SDL_ReleaseGPUShader(device, chunk_frag);

        // 3. Create Chunk Pipeline
        // Input: One u32 per vertex
        var vertex_attrs = [_]c.SDL_GPUVertexAttribute{
            .{ .location = 0, .buffer_slot = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_UINT, .offset = 0 },
        };

        var vertex_bindings = [_]c.SDL_GPUVertexBufferDescription{
            .{
                .slot = 0,
                .pitch = 4, // sizeof(u32)
                .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
                .instance_step_rate = 0,
            },
        };

        var color_targets = [_]c.SDL_GPUColorTargetDescription{
            .{
                .format = c.SDL_GetGPUSwapchainTextureFormat(device, window),
                // Standard Alpha Blending (Optional for opaque chunks, but good default)
                .blend_state = .{
                    .src_color_blendfactor = c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                    .dst_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                    .color_blend_op = c.SDL_GPU_BLENDOP_ADD,
                    .src_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                    .dst_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                    .alpha_blend_op = c.SDL_GPU_BLENDOP_ADD,
                    .enable_blend = false, // Disable for now for performance
                },
            },
        };

        var pipeline_info = std.mem.zeroes(c.SDL_GPUGraphicsPipelineCreateInfo);

        // Shaders
        pipeline_info.vertex_shader = chunk_vert;
        pipeline_info.fragment_shader = chunk_frag;

        // Vertex Input
        pipeline_info.vertex_input_state.num_vertex_attributes = vertex_attrs.len;
        pipeline_info.vertex_input_state.vertex_attributes = &vertex_attrs;
        pipeline_info.vertex_input_state.num_vertex_buffers = vertex_bindings.len;
        pipeline_info.vertex_input_state.vertex_buffer_descriptions = &vertex_bindings;

        // Rasterizer
        pipeline_info.rasterizer_state.cull_mode = c.SDL_GPU_CULLMODE_BACK;
        pipeline_info.rasterizer_state.front_face = c.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE; // Standard GL
        pipeline_info.primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;

        // Depth Stencil (Crucial for 3D)
        pipeline_info.target_info.has_depth_stencil_target = true;
        pipeline_info.target_info.depth_stencil_format = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM;
        pipeline_info.depth_stencil_state.enable_depth_test = true;
        pipeline_info.depth_stencil_state.enable_depth_write = true;
        pipeline_info.depth_stencil_state.compare_op = c.SDL_GPU_COMPAREOP_LESS;

        // Color Target
        pipeline_info.target_info.num_color_targets = 1;
        pipeline_info.target_info.color_target_descriptions = &color_targets;

        const chunk_pipeline = c.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse {
            c.SDL_Log("Pipeline Creation Failed: %s", c.SDL_GetError());
            return error.PipelineFailed;
        };

        // Get initial window size
        var w: i32 = 0;
        var h: i32 = 0;
        _ = c.SDL_GetWindowSize(window, &w, &h);

        return GfxContext{
            .device = device,
            .window = window,
            .chunk_pipeline = chunk_pipeline,
            .depth_texture = null, // Created on first render/resize
            .width = @intCast(w),
            .height = @intCast(h),
        };
    }

    pub fn deinit(self: *GfxContext) void {
        if (self.depth_texture) |tex| c.SDL_ReleaseGPUTexture(self.device, tex);
        c.SDL_ReleaseGPUGraphicsPipeline(self.device, self.chunk_pipeline);
        c.SDL_ReleaseWindowFromGPUDevice(self.device, self.window);
        c.SDL_DestroyGPUDevice(self.device);
    }

    /// Uploads packed chunk mesh data (u32 slice) to the GPU
    pub fn uploadMesh(self: *GfxContext, data: []const u32) !*c.SDL_GPUBuffer {
        const size_bytes = @as(u32, @intCast(data.len * 4));

        // 1. Create Vertex Buffer
        var bci = std.mem.zeroes(c.SDL_GPUBufferCreateInfo);
        bci.usage = c.SDL_GPU_BUFFERUSAGE_VERTEX;
        bci.size = size_bytes;
        const vbo = c.SDL_CreateGPUBuffer(self.device, &bci) orelse return error.VBOFail;

        // 2. Create Transfer Buffer
        var tbci = std.mem.zeroes(c.SDL_GPUTransferBufferCreateInfo);
        tbci.usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
        tbci.size = size_bytes;
        const tbo = c.SDL_CreateGPUTransferBuffer(self.device, &tbci) orelse return error.TBOFail;

        // 3. Map & Copy
        const map_ptr = c.SDL_MapGPUTransferBuffer(self.device, tbo, false);
        if (map_ptr == null) return error.MapFail;

        @memcpy(@as([*]u32, @ptrCast(@alignCast(map_ptr)))[0..data.len], data);
        c.SDL_UnmapGPUTransferBuffer(self.device, tbo);

        // 4. Upload
        const cmd = c.SDL_AcquireGPUCommandBuffer(self.device) orelse return error.CmdFail;
        const pass = c.SDL_BeginGPUCopyPass(cmd);

        var src = std.mem.zeroes(c.SDL_GPUTransferBufferLocation);
        src.transfer_buffer = tbo;
        var dst = std.mem.zeroes(c.SDL_GPUBufferRegion);
        dst.buffer = vbo;
        dst.size = size_bytes;

        c.SDL_UploadToGPUBuffer(pass, &src, &dst, false);
        c.SDL_EndGPUCopyPass(pass);
        _ = c.SDL_SubmitGPUCommandBuffer(cmd);

        c.SDL_ReleaseGPUTransferBuffer(self.device, tbo);

        return vbo;
    }

    pub fn renderChunks(self: *GfxContext, view_proj: math.Mat4, world: *const World) !void {
        const cmd = c.SDL_AcquireGPUCommandBuffer(self.device) orelse return error.CmdFail;

        var swapchain_tex: ?*c.SDL_GPUTexture = null;
        var w: u32 = 0;
        var h: u32 = 0;

        if (!c.SDL_AcquireGPUSwapchainTexture(cmd, self.window, &swapchain_tex, &w, &h)) {
            _ = c.SDL_CancelGPUCommandBuffer(cmd);
            return;
        }

        if (swapchain_tex == null or w == 0 or h == 0) {
            _ = c.SDL_CancelGPUCommandBuffer(cmd);
            return;
        }

        if (self.width != w or self.height != h or self.depth_texture == null) {
            self.width = w;
            self.height = h;

            if (self.depth_texture) |tex| c.SDL_ReleaseGPUTexture(self.device, tex);

            var dci = std.mem.zeroes(c.SDL_GPUTextureCreateInfo);
            dci.type = c.SDL_GPU_TEXTURETYPE_2D;
            dci.format = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM;
            dci.width = w;
            dci.height = h;
            dci.layer_count_or_depth = 1; // Explicitly set to 1
            dci.num_levels = 1; // Explicitly set to 1
            dci.usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET;

            self.depth_texture = c.SDL_CreateGPUTexture(self.device, &dci);

            if (self.depth_texture == null) {
                c.SDL_Log("Failed to create depth texture: %s", c.SDL_GetError());
                _ = c.SDL_CancelGPUCommandBuffer(cmd);
                return;
            }
        }

        const tex = swapchain_tex.?; // We verified it's not null above

        const color_target = c.SDL_GPUColorTargetInfo{
            .texture = tex,
            .clear_color = .{ .r = 0.5, .g = 0.7, .b = 0.9, .a = 1.0 },
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_STORE,
        };

        var depth_target = std.mem.zeroes(c.SDL_GPUDepthStencilTargetInfo);
        depth_target.texture = self.depth_texture;
        depth_target.clear_depth = 1.0;
        depth_target.load_op = c.SDL_GPU_LOADOP_CLEAR;
        depth_target.store_op = c.SDL_GPU_STOREOP_STORE;
        depth_target.stencil_load_op = c.SDL_GPU_LOADOP_DONT_CARE;
        depth_target.stencil_store_op = c.SDL_GPU_STOREOP_DONT_CARE;

        const pass = c.SDL_BeginGPURenderPass(cmd, &color_target, 1, &depth_target);

        c.SDL_BindGPUGraphicsPipeline(pass, self.chunk_pipeline);

        // Binding 0: ViewProj
        c.SDL_PushGPUVertexUniformData(cmd, 0, &view_proj.data, 64);

        var it = world.chunks.iterator();
        while (it.next()) |entry| {
            const chunk = entry.value_ptr.*;

            if (chunk.mesh_buffer) |vbo| {
                if (chunk.vertex_count == 0) continue;

                const pos = entry.key_ptr.*;
                const chunk_pos_vec = [_]f32{ @floatFromInt(pos.x()), @floatFromInt(pos.y()), @floatFromInt(pos.z()), 0.0 };

                // Binding 1: ChunkPos
                c.SDL_PushGPUVertexUniformData(cmd, 1, &chunk_pos_vec, 16);

                const binding = c.SDL_GPUBufferBinding{ .buffer = vbo, .offset = 0 };
                c.SDL_BindGPUVertexBuffers(pass, 0, &binding, 1);
                c.SDL_DrawGPUPrimitives(pass, chunk.vertex_count, 1, 0, 0);
            }
        }

        c.SDL_EndGPURenderPass(pass);
        _ = c.SDL_SubmitGPUCommandBuffer(cmd);
    }
};

fn loadShader(device: *c.SDL_GPUDevice, path: []const u8, num_uniform_bufs: u32, num_samplers: u32) !*c.SDL_GPUShader {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const size = try file.getEndPos();
    const buffer = try std.heap.c_allocator.alloc(u8, size);
    defer std.heap.c_allocator.free(buffer);

    _ = try file.readAll(buffer);

    var info = std.mem.zeroes(c.SDL_GPUShaderCreateInfo);
    info.code_size = size;
    info.code = buffer.ptr;
    info.entrypoint = "main";
    info.format = c.SDL_GPU_SHADERFORMAT_SPIRV;
    info.stage = if (std.mem.indexOf(u8, path, "vert") != null) c.SDL_GPU_SHADERSTAGE_VERTEX else c.SDL_GPU_SHADERSTAGE_FRAGMENT;
    info.num_uniform_buffers = num_uniform_bufs;
    info.num_samplers = num_samplers;

    return c.SDL_CreateGPUShader(device, &info) orelse return error.ShaderError;
}
