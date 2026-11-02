#include <metal_stdlib>
using namespace metal;
struct ColourConfig { uint tenBit; uint fullRange; uint bt2020; uint pq; uint toneMap; float referenceWhiteNits; };
float3 inverse709(float3 v) {
    return select(v / 4.5f, pow(max((v + 0.099f) / 1.099f, 0.0f), float3(1.0f / 0.45f)), v >= 0.081f);
}
float3 pqNits(float3 value) {
    const float m1 = 2610.0f/16384.0f, m2 = 2523.0f/32.0f;
    const float c1 = 3424.0f/4096.0f, c2 = 2413.0f/128.0f, c3 = 2392.0f/128.0f;
    float3 p = pow(clamp(value, 0.0f, 1.0f), float3(1.0f/m2));
    return 10000.0f * pow(max(p-c1, 0.0f) / max(c2-c3*p, 1e-7f), float3(1.0f/m1));
}
float3 linear709(float3 value, constant ColourConfig &config) {
    float3 rgb = config.pq ? pqNits(value) / config.referenceWhiteNits : inverse709(max(value, 0.0f));
    if(config.bt2020) {

        rgb = float3(dot(rgb, float3(1.660491f,-0.587641f,-0.072850f)),
                     dot(rgb, float3(-0.124550f,1.132900f,-0.008349f)),
                     dot(rgb, float3(-0.018151f,-0.100579f,1.118730f)));
    }
    if(config.toneMap) {

        float luminance = max(dot(rgb, float3(0.2126f,0.7152f,0.0722f)), 0.0f);
        rgb = clamp(rgb / (1.0f + luminance), 0.0f, 1.0f);
    }
    return rgb;
}
float3 convertYUV(float3 raw, constant ColourConfig &config) {
    float maxCode = config.tenBit ? 1023.0f : 255.0f;

    float3 code = raw * (config.tenBit ? 65535.0f/64.0f : 255.0f);
    float scale = config.tenBit ? 4.0f : 1.0f;
    float y = config.fullRange ? code.x / maxCode : (code.x - 16.0f*scale)/(219.0f*scale);
    float2 uv = (code.yz - 128.0f*scale) / (config.fullRange ? maxCode : 224.0f*scale);
    float kr = config.bt2020 ? 0.2627f : 0.2126f;
    float kb = config.bt2020 ? 0.0593f : 0.0722f;
    float r = y + 2.0f*(1.0f-kr)*uv.y;
    float b = y + 2.0f*(1.0f-kb)*uv.x;
    float g = (y - kr*r - kb*b)/(1.0f-kr-kb);
    return linear709(float3(r,g,b), config);
}
kernel void colour_planes(texture2d<float, access::sample> y [[texture(0)]],
                          texture2d<float, access::sample> uv [[texture(1)]],
                          texture2d<half, access::write> output [[texture(2)]],
                          constant ColourConfig &config [[buffer(0)]],
                          uint2 position [[thread_position_in_grid]]) {
    if(position.x >= output.get_width() || position.y >= output.get_height()) return;
    constexpr sampler sampling(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 point = (float2(position)+0.5f)/float2(output.get_width(),output.get_height());
    output.write(half4(float4(convertYUV(float3(y.sample(sampling,point).r,uv.sample(sampling,point).rg),config),1.0f)),position);
}

kernel void test_colour(device const float4 *input [[buffer(0)]], device float4 *output [[buffer(1)]],
                        constant ColourConfig &config [[buffer(2)]], uint i [[thread_position_in_grid]]) {
    output[i] = float4(convertYUV(input[i].xyz,config),1.0f);
}
