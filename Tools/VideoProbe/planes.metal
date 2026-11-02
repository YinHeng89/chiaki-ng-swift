#include <metal_stdlib>
using namespace metal;


kernel void inspect_planes(texture2d<float, access::sample> y [[texture(0)]],
                           texture2d<float, access::sample> uv [[texture(1)]],
                           texture2d<half, access::write> output [[texture(2)]],
                           uint2 position [[thread_position_in_grid]]) {
    if (position.x >= output.get_width() || position.y >= output.get_height()) return;
    constexpr sampler sampling(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 point = (float2(position) + 0.5) / float2(output.get_width(), output.get_height());
    float luma = y.sample(sampling, point).r;
    float2 chroma = uv.sample(sampling, point).rg;
    output.write(half4(float4(luma, chroma, 1.0)), position);
}
