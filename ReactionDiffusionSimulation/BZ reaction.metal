//
//  BZ.metal
//  ReactionDiffusionSimulation
//
//  Created by Dennis Barzanoff on 25.11.23.
//

#include <metal_stdlib>
using namespace metal;


constant float eps = 0.0243f;
constant float f = 1.4f;
constant float phi = 0.054f;
constant float q = 0.002f;
constant float Du = 0.45f;
constant float dt = 0.01f;

float laplacian(texture2d<float, access::read_write> input, uint2 gid, float u);

kernel void bz_compute(texture2d<float, access::read_write> input [[texture(0)]],
                       texture2d<float, access::read_write> output [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
//    float4 res = float4(1.0f, 1.0f, 1.0f, 1.0f);
//    output.write(res, gid);

    // Check gid is within the boundaries of our data
    if (gid.x < input.get_width() && gid.y < input.get_height()) {
        // Get the value from texture
        float4 value = input.read(gid);
            
        // Perform your computations...
        float u = value.r;
        float v = value.g;

        float uLaplacian = laplacian(input, gid, u);

        float du = ((1 / eps) * (u - (u * u) - ((f * v) + phi) * ((u - q) / (u + q))) + Du * uLaplacian);
        float dv = (u - v);

        float newU = clamp(u + (du * dt), 0.0f, 1.0f);
        float newV = clamp(v + (dv * dt), 0.0f, 1.0f);

        float4 result = float4(newU, newV, value.b, 1.0f);

        // Write the result to texture
        output.write(result, gid);
    }
}


float laplacian(texture2d<float, access::read_write> input, uint2 gid, float u) {

    // Read adjacent cells
    float adjacentCells = input.read(gid + uint2(-1, 0)).r   // left
                        + input.read(gid + uint2(1, 0)).r    // right
                        + input.read(gid + uint2(0, -1)).r   // up
                        + input.read(gid + uint2(0, 1)).r;   // down

    return (adjacentCells - (4 * u)) / (0.25 * 0.25);
}

