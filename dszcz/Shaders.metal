#include <metal_stdlib>
#include "SharedConfig.h"
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


kernel void
addDrops(
         constant ushort4* dropConfigs [[buffer(0)]],
         texture2d<float, access::read_write> outTexture [[texture(0)]],
         uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }

    float4 currPixel = outTexture.read(gid);
    float2 pixelPos = float2(gid);

    for (uint i = 0; i < DROPS_PER_PASS; ++i) {
        ushort2 dropLocation = dropConfigs[i].xy;
        float dropRadius = dropConfigs[i].z;
        float dropStrength = float(dropConfigs[i].w) / 1000.0;

        // Early-out bounding box
        if (abs(pixelPos.x - dropLocation.x) > dropRadius ||
            abs(pixelPos.y - dropLocation.y) > dropRadius) {
            continue;
        }

        float dist = length(pixelPos - float2(dropLocation));
        if (dist > dropRadius) {
            continue;
        }

        float drop = 1.0 - (dist / dropRadius);
        drop = 1.0 - cos(drop * M_PI_F);
        currPixel.r += drop * dropStrength;
    }

    outTexture.write(currPixel, gid);
}


constant float damping = 0.995;
constant uint2 dx = uint2(1, 0);
constant uint2 dy = uint2(0, 1);
kernel void
moveWaves(
          texture2d<float, access::read> inTexture [[texture(0)]],
          texture2d<float, access::read_write> outTexture [[texture(1)]],
          uint2 gid [[thread_position_in_grid]]
) {
    float4 currPixel = outTexture.read(gid);

    float next = (
                   inTexture.read(gid - dx).r + // left
                   inTexture.read(gid + dx).r + // right
                   inTexture.read(gid - dy).r + // up
                   inTexture.read(gid + dy).r   // down
    ) / 2 - currPixel.r;

    currPixel.r = next * damping;
    
    outTexture.write(currPixel, gid);
}
