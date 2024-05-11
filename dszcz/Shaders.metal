#include <metal_stdlib>
using namespace metal;

vertex float4 vertexShader(unsigned int vid [[ vertex_id ]]) {
    const float4x4 vertices = float4x4(float4(-1,  1, 0, 1),
                                       float4( 1,  1, 0, 1),
                                       float4(-1, -1, 0, 1),
                                       float4( 1, -1, 0, 1));
    return vertices[vid];
}

fragment float4 fragmentShader(
                              float4 pos [[position]],
                              constant float2& res [[buffer(0)]],
                              constant float& time [[buffer(1)]]
) {
    float2 uv = pos.xy / res.xy;
    float3 col = 0.5 + 0.5*cos(time + uv.xyx + float3(0, 2, 4));
    return float4(col[0], col[1], col[2], 0.5);
}
