//
//  red.metal
//  ReactionDiffusionSimulation
//
//  Created by Dennis Barzanoff on 26.11.23.
//

#include <metal_stdlib>
using namespace metal;


kernel void set_color(texture2d<float, access::write> output [[texture(0)]],
                      constant uint2 &center [[ buffer(0) ]],
                      constant uint &radius [[ buffer(1) ]],
                      constant float4 &color [[ buffer(2) ]],
                      uint2 gridPosition [[thread_position_in_grid]])
{

    int dx = center.x - gridPosition.x;
    int dy = center.y - gridPosition.y;
    
    if ((dx*dx + dy*dy) <= radius*radius) {
        output.write(color, gridPosition);
    }
}
