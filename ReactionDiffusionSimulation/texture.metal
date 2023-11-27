//
//  texture.metal
//  ReactionDiffusionSimulation
//
//  Created by Dennis Barzanoff on 26.11.23.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};


fragment float4 fragment_main(VertexOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                sampler textureSampler [[sampler(0)]]) {
    // Simply sample the texture
    return tex.sample(textureSampler, in.texCoord);
}

vertex VertexOut vertex_main(constant VertexIn *vertexArray [[buffer(0)]],
                             uint vertexID [[vertex_id]]) {
    VertexOut out;
    out.position = vertexArray[vertexID].position; // Pass-through position
    out.texCoord = vertexArray[vertexID].texCoord; // Pass-through texture coordinate
    return out;
}
