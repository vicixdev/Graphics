#include <metal_stdlib>

using namespace metal;

struct GpuTextureDescriptor {
	uint64_t _desc[4];
};

struct FragmentData {};

struct FragmentIn {
	float2 uv;
};

device texture2d<float>& getTextureAt(device GpuTextureDescriptor* heap, uint index) {
	device uint64_t& textureId = heap[index]._desc[0];
	return reinterpret_cast<device texture2d<float>&>(textureId);
}
 
[[host_name("main")]]
fragment float4 vertexMain(
		FragmentIn 		fragmentIn	[[stage_in]],
	device	FragmentData&		fragmentData	[[buffer(0)]],
	device	GpuTextureDescriptor*	textureHeap	[[buffer(1)]]
) {
	constexpr metal::sampler s(metal::filter::nearest);
	device texture2d<float>& tex = getTextureAt(textureHeap, 1);
	
	return tex.sample(s, fragmentIn.uv);
}

