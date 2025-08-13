#include <metal_stdlib>
using namespace metal;

struct GPUParameters {
    float minX;
    float minZ;
    float gridResolution;
    uint  width;
    uint  height;
    float txPowerAt1mDbm;
    float pathLossExponent;
    float wallAttenuationDb;
    float maxDistanceMeters;
};

struct WallSegmentGPU { float ax; float az; float bx; float bz; };

bool segments_intersect(float2 p1, float2 p2, float2 q1, float2 q2) {
    auto cross = [](float2 a, float2 b) -> float { return a.x * b.y - a.y * b.x; };
    float2 r = p2 - p1;
    float2 s = q2 - q1;
    float denom = cross(r, s);
    if (fabs(denom) < 1e-6) return false; // parallel
    float t = cross((q1 - p1), s) / denom;
    float u = cross((q1 - p1), r) / denom;
    return t >= 0.0 && t <= 1.0 && u >= 0.0 && u <= 1.0;
}

kernel void rf_propagation_kernel(
    device const WallSegmentGPU*  segs        [[ buffer(0) ]],
    device const uint*            segCountBuf [[ buffer(1) ]],
    device const float2*          routers     [[ buffer(2) ]],
    device const uint*            routerCount [[ buffer(3) ]],
    device const GPUParameters*   params      [[ buffer(4) ]],
    device float*                 outGrid     [[ buffer(5) ]],
    uint2 tid [[ thread_position_in_grid ]]
) {
    uint W = params->width;
    uint H = params->height;
    if (tid.x >= W || tid.y >= H) return;

    float x = params->minX + float(tid.x) * params->gridResolution;
    float z = params->minZ + float(tid.y) * params->gridResolution;
    float2 p = float2(x, z);

    uint segCount = *segCountBuf;
    uint rCount = *routerCount;

    float bestRssi = -150.0;
    for (uint r = 0; r < rCount; ++r) {
        float2 tx = routers[r];
        float dx = p.x - tx.x;
        float dz = p.y - tx.y;
        float d = max(0.1, sqrt(dx*dx + dz*dz));
        if (d > params->maxDistanceMeters) continue;

        // Count wall intersections
        int intersections = 0;
        for (uint i = 0; i < segCount; ++i) {
            float2 a = float2(segs[i].ax, segs[i].az);
            float2 b = float2(segs[i].bx, segs[i].bz);
            intersections += segments_intersect(tx, p, a, b) ? 1 : 0;
        }

        // Path loss model
        float fspl = 10.0 * params->pathLossExponent * log10(d);
        float wallLoss = float(intersections) * params->wallAttenuationDb;
        float rssi = params->txPowerAt1mDbm - fspl - wallLoss;
        bestRssi = max(bestRssi, rssi);
    }

    // Normalize to 0..1
    float normalized = clamp((bestRssi + 100.0) / 100.0, 0.0, 1.0);
    outGrid[tid.y * W + tid.x] = normalized;
}