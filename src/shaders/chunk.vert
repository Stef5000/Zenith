#version 450

layout(location = 0) in uint in_Data;

layout(set = 1, binding = 0) uniform ViewProj {
    mat4 view_proj;
};

layout(set = 1, binding = 1) uniform ChunkData {
    vec4 chunk_pos;
};

layout(location = 0) out vec2 v_UV;
layout(location = 1) out float v_Light;

void main() {
    // --- Unpack Data (Updated for 6-bit coordinates) ---
    // Mask 0x3F = 63 (6 bits)

    float x = float(in_Data & 0x3Fu);
    float y = float((in_Data >> 6) & 0x3Fu);
    float z = float((in_Data >> 12) & 0x3Fu);

    uint face = (in_Data >> 18) & 0x7u;
    uint tex_id = (in_Data >> 21) & 0xFFu; // Available for fragment shader later
    uint uv_id = (in_Data >> 29) & 0x3u;

    // --- Calculate World Position ---
    vec3 local_pos = vec3(x, y, z);
    vec3 world_pos = chunk_pos.xyz * 32.0 + local_pos;

    // --- UVs ---
    vec2 uvs[4] = vec2[](
            vec2(0, 1), vec2(1, 1), vec2(1, 0), vec2(0, 0)
        );
    v_UV = uvs[uv_id];

    // --- Lighting ---
    float light_values[6] = float[](0.6, 1.0, 0.8, 0.8, 0.6, 0.6);
    v_Light = light_values[face];

    gl_Position = view_proj * vec4(world_pos, 1.0);
}
