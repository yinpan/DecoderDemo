//
//  YUVShader.metal
//  DecoderDemo
//
//  Created by yinpan on 2024/6/5.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut yuvVertexShader(uint vertexID [[vertex_id]]) {
    float4 positions[4] = {
        float4(-1.0, -1.0, 0.0, 1.0),
        float4( 1.0, -1.0, 0.0, 1.0),
        float4(-1.0,  1.0, 0.0, 1.0),
        float4( 1.0,  1.0, 0.0, 1.0),
    };

    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0),
    };

    VertexOut out;
    out.position = positions[vertexID];
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 BiYuvFragmentShader(VertexOut in [[stage_in]],
                               texture2d<float> yTexture [[texture(0)]],
                               texture2d<float> uTexture [[texture(1)]],
                               texture2d<float> vTexture [[texture(2)]]) {
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);

    float y = yTexture.sample(textureSampler, in.texCoord).r;
    float u = uTexture.sample(textureSampler, in.texCoord).r - 0.5;
    float v = vTexture.sample(textureSampler, in.texCoord).r - 0.5;

    float r = y + 1.402 * v;
    float g = y - 0.344 * u - 0.714 * v;
    float b = y + 1.772 * u;

    return float4(r, g, b, 1.0);
}

fragment float4 yuvFragmentShader(VertexOut in [[stage_in]],
                               texture2d<float, access::sample> yTexture [[texture(0)]],
                               texture2d<float, access::sample> uvTexture [[texture(1)]]) {
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);

    float y = yTexture.sample(textureSampler, in.texCoord).r;
    
    // Sample UV texture
    float2 uv = uvTexture.sample(textureSampler, in.texCoord).rg;
    float u = uv.x - 0.5;
    float v = uv.y - 0.5;

    float r = y + 1.402 * v;
    float g = y - 0.344 * u - 0.714 * v;
    float b = y + 1.772 * u;

    return float4(r, g, b, 1.0);
}
