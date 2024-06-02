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
               constant float2& res [[buffer(0)]],
               constant float& time [[buffer(1)]],
               texture2d<float, access::sample> screenTexture [[texture(0)]],
               texture2d<float, access::sample> rainTexture [[texture(1)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 uv = pos.xy / res.xy;

    float4 f = screenTexture.sample(s, uv);
    float4 g = rainTexture.sample(s, uv);

    return float4(f.rgb * (1 - g.b), 1);
}


constant float dropRadius = 20.0;
constant float strength = 0.14;

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
    currPixel.b += drop * strength;

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
                   inTexture.read(gid - dx).b +
                   inTexture.read(gid + dx).b +
                   inTexture.read(gid - dy).b +
                   inTexture.read(gid + dy).b
    ) / 2 - currPixel.b;
    next = next * damping;
    
    currPixel.b = next;

    outTexture.write(currPixel, gid);
}
