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
constant float phi_active = 0.054f;
constant float phi_passive = 0.0975f;
constant float q = 0.002f;
constant float Du = 0.45f;
constant float dt = 0.002f;

constant float scaleFactor = 1/5.0f; // 5px/mm
constant float lightHeight = 130; // 130mm

constant float M_PI = 3.149516f;

struct Seed {
    uint seed1;
    uint seed2;
};

struct ReactionConfig {
    Seed seed;
    float noiseScale;
};


float get_random_float(uint seed);
float gaussianNoise(float mean, float stdDev, constant Seed& seed);
float laplacian(texture2d<float, access::read_write> input, uint2 gid, float u);
float scale(float value, float minRange, float maxRange);

kernel void bz_compute(texture2d<float, access::read_write> input [[texture(0)]],
                       texture2d<float, access::read_write> output [[texture(1)]],
                       constant ReactionConfig& config [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]],
                       device uint2* debugInputLocation [[buffer(1)]],
                       device float* debugValue [[buffer(2)]]) {
    if (gid.x < input.get_width() && gid.y < input.get_height()) {
        // Get the value from texture
        float4 value = input.read(gid);
        uint2 center = uint2(input.get_width() / 2, input.get_height() / 2);
        // Calculate the distance from the center using Pythagorean theorem
        float dx = float(center.x) - gid.x;
        float dy = float(center.y) - gid.y;

        float distance = sqrt(dx * dx + dy * dy);

        // Scale the distance from pixels to mm using the scaling factor (px/mm)
        float scaledDistance = distance * scaleFactor;

        // Calculate the illumination percentage based on the distance
        float illumination = 1.0f / sqrt(1.0f + pow(scaledDistance / lightHeight, 2.0f));
        
        // Perform your computations...
        float u = value.r;
        float v = value.g;
        
        // Calculate phi based on illumination; phi is phi_active when there's light (i.e., illumination is low)
        float phi = scale(1 - value.b, phi_passive, phi_active);
        if (value.b == 1) { 
            // we can only add less or more light to the passive component,
            // the active is always protected from light
//            illumination = 0.5;
            phi = scale(illumination, phi_active, phi_passive);
        }
        
        // set debug values
        if (gid.x == debugInputLocation->x && gid.y == debugInputLocation->y) {
            *debugValue =  illumination;
        }
        
        // Perform the reaction-diffusion computation
        float uLaplacian = laplacian(input, gid, u);
        
        float du = ((1 / eps) * (u - (u * u) - ((f * v) + phi) * ((u - q) / (u + q))) + Du * uLaplacian);
        float dv = (u - v);
        
        float newU = clamp(u + (du * dt), 0.0f, 1.0f);
        float newV = clamp(v + (dv * dt), 0.0f, 1.0f);

        // Combine the computed values into a new color
        float4 result = float4(newU, newV, value.b, 1.0f);

        // Write the result to the output texture
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


float scale(float value, float minRange, float maxRange) {
    return minRange + (value / 1) * (maxRange - minRange);
}

float get_random_float(uint seed) {
    float result = fract(sin(float(seed) * 1.61803398875f) * 4253.548887f);
    if (result == 0.0f) {
         result = 0.5f; // or choose another appropriate non-zero value in the range (0,1)
    }
    return result;
}

float gaussianNoise(float mean, float stdDev, constant Seed& seed){
    // Use Box-Muller transform to generate a point from normal distribution.
    float u1 = get_random_float(seed.seed1);
    float u2 = get_random_float(seed.seed2);
    float randStdNormal = sqrt(-2.0 * log(u1)) * sin(2.0 * M_PI * u2);
    return mean + stdDev * randStdNormal;
}
