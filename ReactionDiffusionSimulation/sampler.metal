//
//  sampler.metal
//  ReactionDiffusionSimulation
//
//  Created by Dennis Barzanoff on 22.12.23.
//

#include <metal_stdlib>
#include "common.h"
using namespace metal;


kernel void samplingShader(texture2d<float, access::read_write> colorTexture [[ texture(0) ]],
                           constant int2 &pos [[ buffer(0) ]],
                           device float4 &outColor [[ buffer(1) ]]) {
    // Convert position to integer as texture index should be in integer
    // Sample color of the texture at 'index'
    
    outColor = colorTexture.read(ushort2(pos));
}
