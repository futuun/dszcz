#include <metal_stdlib>
using namespace metal;

vertex float4
vertexShader(unsigned int vid [[ vertex_id ]]) {
    const float4x4 vertices = float4x4(float4(-1,  1, 0, 1),
                                       float4( 1,  1, 0, 1),
                                       float4(-1, -1, 0, 1),
                                       float4( 1, -1, 0, 1));
    return vertices[vid];
}


fragment float4
fragmentShader(
               float4 pos [[position]],
               texture2d<float, access::sample> screenTexture [[texture(0)]],
               texture2d<float, access::sample> rainTexture [[texture(1)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 screenTextureRes = float2(screenTexture.get_width(), screenTexture.get_height());
    float2 rainTextureRes = float2(rainTexture.get_width(), rainTexture.get_height());

    float2 uv = pos.xy / screenTextureRes;
    float2 delta = 1.0 / rainTextureRes;

    float height = rainTexture.sample(s, uv.xy).r;
    float heightX = rainTexture.sample(s, float2(uv.x - delta.x, uv.y)).r;
    float heightY = rainTexture.sample(s, float2(uv.x, uv.y - delta.y)).r;

    float3 dx = float3(delta.x, heightX - height, 0.0);
    float3 dy = float3(0.0, heightY - height, delta.y);
    float2 offset = -normalize(cross(dy, dx)).xz;
    float specular = pow(max(0.0, dot(offset, normalize(float2(-0.6, 1.0)))), 4.0);

    float4 f = screenTexture.sample(s, uv + (offset * delta));

    return f  + specular + (height * 4);
}

constant float dropRadius = 20.0;
constant float strength = 0.01;

kernel void
addDrops(
         constant uint2& dropLocation [[buffer(0)]],
         texture2d<float, access::read_write> outTexture [[texture(0)]],
         uint2 gid [[thread_position_in_grid]]
) {
    if((gid.x >= outTexture.get_width()) || (gid.y >= outTexture.get_height())) {
        return;
    }

    float4 currPixel = outTexture.read(gid);
    float drop = max(0.0, 1.0 - (length(float2(gid) - float2(dropLocation)) / dropRadius));
    drop = 1 - cos(drop * M_PI_F);
    currPixel.r += drop * strength;

    outTexture.write(currPixel, gid);
}


constant float damping = 0.995;

kernel void
moveWaves(
          texture2d<float, access::read> inTexture [[texture(0)]],
          texture2d<float, access::read_write> outTexture [[texture(1)]],
          uint2 gid [[thread_position_in_grid]]
) {
    float4 currPixel = outTexture.read(gid);

    uint2 dx = uint2(1, 0);
    uint2 dy = uint2(0, 1);

    float next = (
                   inTexture.read(gid - dx).r +
                   inTexture.read(gid + dx).r +
                   inTexture.read(gid - dy).r +
                   inTexture.read(gid + dy).r
    ) / 2 - currPixel.r;
    next = next * damping;

    currPixel.r = next;

    outTexture.write(currPixel, gid);
}
