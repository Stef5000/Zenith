#version 450

layout(location = 0) in vec2 v_UV;
layout(location = 1) in float v_Light;
layout(location = 2) in flat uint v_TexID;

layout(set = 2, binding = 0) uniform sampler2DArray u_Textures;

layout(location = 0) out vec4 out_Color;

void main() {
    vec4 tex_color = texture(u_Textures, vec3(v_UV, float(v_TexID)));
    if (tex_color.a < 0.1) discard;

    out_Color = vec4(tex_color.rgb * v_Light, tex_color.a);
}
