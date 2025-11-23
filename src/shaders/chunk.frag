#version 450

layout(location = 0) in vec2 v_UV;
layout(location = 1) in float v_Light;

layout(location = 0) out vec4 out_Color;

void main() {
    // Debug: UV Grid
    vec3 base_color = vec3(0.5, 0.8, 0.5); // Grassy Green

    // Create a little frame around the block
    if (v_UV.x < 0.05 || v_UV.x > 0.95 || v_UV.y < 0.05 || v_UV.y > 0.95) {
        base_color = vec3(0.3, 0.6, 0.3);
    }

    out_Color = vec4(base_color * v_Light, 1.0);
}
