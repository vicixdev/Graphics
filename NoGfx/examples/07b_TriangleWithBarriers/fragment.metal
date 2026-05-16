#include <metal_stdlib>

using namespace metal;

struct GpuTextureDescriptor {
	uint64_t _desc[4];
};

struct FragmentData {};

struct FragmentIn {
	float3 color;
};

[[host_name("main")]]
fragment float4 vertexMain(
		FragmentIn 		fragmentIn	[[stage_in]],
	device	FragmentData&		fragmentData	[[buffer(0 )]],
	device	GpuTextureDescriptor*	textureHeap	[[buffer(15)]]
) {
	float4 color = float4(fragmentIn.color, 1.0);

	return color;
}
 
