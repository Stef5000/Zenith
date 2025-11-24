const std = @import("std");
const c = @import("../c.zig").c;
const math = @import("../math/math.zig");
const World = @import("../world/world.zig").World;
const coord = @import("../world/coord.zig");
const tex_loader = @import("texture_loader.zig");

pub const GfxContext = struct {
    device: *c.SDL_GPUDevice,
    window: *c.SDL_Window,

    chunk_pipeline: *c.SDL_GPUGraphicsPipeline,

    depth_texture: ?*c.SDL_GPUTexture,

    width: u32,
    height: u32,

    texture_array: ?*c.SDL_GPUTexture,
    default_sampler: *c.SDL_GPUSampler,

    pub fn init(window: *c.SDL_Window) !GfxContext {
        const device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, true, null) orelse return error.GpuInitFailed;
        errdefer c.SDL_DestroyGPUDevice(device);

        if (!c.SDL_ClaimWindowForGPUDevice(device, window)) {
            return error.WindowClaimFailed;
        }
        const chunk_vert = try loadShader(device, "src/shaders/chunk.vert.spv", 2, 0);
        const chunk_frag = try loadShader(device, "src/shaders/chunk.frag.spv", 0, 1);
        defer c.SDL_ReleaseGPUShader(device, chunk_vert);
        defer c.SDL_ReleaseGPUShader(device, chunk_frag);

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

        pipeline_info.vertex_shader = chunk_vert;
        pipeline_info.fragment_shader = chunk_frag;

        pipeline_info.vertex_input_state.num_vertex_attributes = vertex_attrs.len;
        pipeline_info.vertex_input_state.vertex_attributes = &vertex_attrs;
        pipeline_info.vertex_input_state.num_vertex_buffers = vertex_bindings.len;
        pipeline_info.vertex_input_state.vertex_buffer_descriptions = &vertex_bindings;

        pipeline_info.rasterizer_state.cull_mode = c.SDL_GPU_CULLMODE_BACK;
        pipeline_info.rasterizer_state.front_face = c.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE; // Standard GL
        pipeline_info.primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;

        pipeline_info.target_info.has_depth_stencil_target = true;
        pipeline_info.target_info.depth_stencil_format = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM;
        pipeline_info.depth_stencil_state.enable_depth_test = true;
        pipeline_info.depth_stencil_state.enable_depth_write = true;
        pipeline_info.depth_stencil_state.compare_op = c.SDL_GPU_COMPAREOP_LESS;

        pipeline_info.target_info.num_color_targets = 1;
        pipeline_info.target_info.color_target_descriptions = &color_targets;

        const chunk_pipeline = c.SDL_CreateGPUGraphicsPipeline(device, &pipeline_info) orelse {
            c.SDL_Log("Pipeline Creation Failed: %s", c.SDL_GetError());
            return error.PipelineFailed;
        };

        var sampler_info = std.mem.zeroes(c.SDL_GPUSamplerCreateInfo);
        sampler_info.min_filter = c.SDL_GPU_FILTER_NEAREST; // Pixelated look
        sampler_info.mag_filter = c.SDL_GPU_FILTER_NEAREST;
        sampler_info.mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST;
        sampler_info.address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_REPEAT;
        sampler_info.address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_REPEAT;
        sampler_info.address_mode_w = c.SDL_GPU_SAMPLERADDRESSMODE_REPEAT;

        const sampler = c.SDL_CreateGPUSampler(device, &sampler_info) orelse return error.SamplerFail;

        var w: i32 = 0;
        var h: i32 = 0;
        _ = c.SDL_GetWindowSize(window, &w, &h);

        return GfxContext{
            .device = device,
            .window = window,
            .chunk_pipeline = chunk_pipeline,
            .depth_texture = null,
            .width = @intCast(w),
            .height = @intCast(h),
            .texture_array = null,
            .default_sampler = sampler,
        };
    }

    pub fn deinit(self: *GfxContext) void {
        if (self.texture_array) |t| c.SDL_ReleaseGPUTexture(self.device, t);
        c.SDL_ReleaseGPUSampler(self.device, self.default_sampler);
        if (self.depth_texture) |tex| c.SDL_ReleaseGPUTexture(self.device, tex);
        c.SDL_ReleaseGPUGraphicsPipeline(self.device, self.chunk_pipeline);
        c.SDL_ReleaseWindowFromGPUDevice(self.device, self.window);
        c.SDL_DestroyGPUDevice(self.device);
    }

    pub fn uploadMesh(self: *GfxContext, data: []const u32) !*c.SDL_GPUBuffer {
        const size_bytes = @as(u32, @intCast(data.len * 4));
        var bci = std.mem.zeroes(c.SDL_GPUBufferCreateInfo);
        bci.usage = c.SDL_GPU_BUFFERUSAGE_VERTEX;
        bci.size = size_bytes;
        const vbo = c.SDL_CreateGPUBuffer(self.device, &bci) orelse return error.VBOFail;
        var tbci = std.mem.zeroes(c.SDL_GPUTransferBufferCreateInfo);
        tbci.usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
        tbci.size = size_bytes;
        const tbo = c.SDL_CreateGPUTransferBuffer(self.device, &tbci) orelse return error.TBOFail;
        const map_ptr = c.SDL_MapGPUTransferBuffer(self.device, tbo, false);
        if (map_ptr == null) return error.MapFail;

        @memcpy(@as([*]u32, @ptrCast(@alignCast(map_ptr)))[0..data.len], data);
        c.SDL_UnmapGPUTransferBuffer(self.device, tbo);

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

        if (swapchain_tex == null) {
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
        const tex = swapchain_tex.?;

        if (self.width != w or self.height != h or self.depth_texture == null) {
            self.width = w;
            self.height = h;
            if (self.depth_texture) |d| c.SDL_ReleaseGPUTexture(self.device, d);
            var dci = std.mem.zeroes(c.SDL_GPUTextureCreateInfo);
            dci.type = c.SDL_GPU_TEXTURETYPE_2D;
            dci.format = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM;
            dci.width = w;
            dci.height = h;
            dci.layer_count_or_depth = 1;
            dci.num_levels = 1;
            dci.usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET;
            self.depth_texture = c.SDL_CreateGPUTexture(self.device, &dci);
        }

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

        const pass = c.SDL_BeginGPURenderPass(cmd, &color_target, 1, &depth_target);

        c.SDL_BindGPUGraphicsPipeline(pass, self.chunk_pipeline);
        c.SDL_PushGPUVertexUniformData(cmd, 0, &view_proj.data, 64);

        if (self.texture_array) |tex_array| {
            var binding = c.SDL_GPUTextureSamplerBinding{ .texture = tex_array, .sampler = self.default_sampler };
            c.SDL_BindGPUFragmentSamplers(pass, 0, &binding, 1);
        }

        var it = world.chunks.iterator();
        while (it.next()) |entry| {
            const chunk = entry.value_ptr.*;
            if (chunk.mesh_buffer) |vbo| {
                if (chunk.vertex_count == 0) continue;
                const pos = entry.key_ptr.*;
                const chunk_pos_vec = [_]f32{ @floatFromInt(pos.x()), @floatFromInt(pos.y()), @floatFromInt(pos.z()), 0.0 };
                c.SDL_PushGPUVertexUniformData(cmd, 1, &chunk_pos_vec, 16);
                const v_binding = c.SDL_GPUBufferBinding{ .buffer = vbo, .offset = 0 };
                c.SDL_BindGPUVertexBuffers(pass, 0, &v_binding, 1);
                c.SDL_DrawGPUPrimitives(pass, chunk.vertex_count, 1, 0, 0);
            }
        }
        c.SDL_EndGPURenderPass(pass);
        _ = c.SDL_SubmitGPUCommandBuffer(cmd);
    }

    pub fn createTextureArray(self: *GfxContext, data: tex_loader.TextureArrayData) !void {
        var tci: c.SDL_GPUTextureCreateInfo = .{
            .type = c.SDL_GPU_TEXTURETYPE_2D_ARRAY,
            .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
            .usage = c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
            .width = data.width,
            .height = data.height,
            .layer_count_or_depth = data.layer_count,
            .num_levels = 1,
            .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
            .props = 0,
        };

        const tex = c.SDL_CreateGPUTexture(self.device, &tci) orelse return error.TexCreateFail;
        self.texture_array = tex;
        const size_bytes = @as(u32, @intCast(data.pixels.len));
        var tbci = std.mem.zeroes(c.SDL_GPUTransferBufferCreateInfo);
        tbci.usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD;
        tbci.size = size_bytes;
        const tbo = c.SDL_CreateGPUTransferBuffer(self.device, &tbci) orelse return error.TBOFail;

        const map_ptr = c.SDL_MapGPUTransferBuffer(self.device, tbo, false);
        if (map_ptr == null) return error.MapFail;

        @memcpy(@as([*]u8, @ptrCast(@alignCast(map_ptr)))[0..data.pixels.len], data.pixels);
        c.SDL_UnmapGPUTransferBuffer(self.device, tbo);

        const cmd = c.SDL_AcquireGPUCommandBuffer(self.device) orelse return error.CmdFail;
        const pass = c.SDL_BeginGPUCopyPass(cmd);

        const layer_size = data.width * data.height * 4; // 4 bytes per pixel (RGBA8888)

        for (0..data.layer_count) |i| {
            var src = std.mem.zeroes(c.SDL_GPUTextureTransferInfo);
            src.transfer_buffer = tbo;
            src.offset = @as(u32, @intCast(i * layer_size)); // Offset into the TBO
            src.pixels_per_row = 0;
            src.rows_per_layer = 0;

            var dst = std.mem.zeroes(c.SDL_GPUTextureRegion);
            dst.texture = tex;
            dst.w = data.width;
            dst.h = data.height;
            dst.d = 1; // Depth must be 1 for 2D Array slices
            dst.layer = @as(u32, @intCast(i)); // Target the specific array layer

            c.SDL_UploadToGPUTexture(pass, &src, &dst, false);
        }
        c.SDL_EndGPUCopyPass(pass);
        _ = c.SDL_SubmitGPUCommandBuffer(cmd);
        c.SDL_ReleaseGPUTransferBuffer(self.device, tbo);
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
