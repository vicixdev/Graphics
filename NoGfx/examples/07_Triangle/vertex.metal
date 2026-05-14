#include <metal_stdlib>

using namespace metal;

struct VertexIn {
	device packed_float3*	positions;
	device packed_float3*	colors;
};

struct VertexOut {
	float4 position [[position]];
	float3 color;
};

[[host_name("main")]]
vertex VertexOut vertexMain(
		uint		vertexIndex	[[vertex_id]],
	device	const VertexIn&	vertexData	[[buffer(0)]]
) {
	float3 position	= float3(vertexData.positions[vertexIndex]);
	float3 color	= float3(vertexData.colors[vertexIndex]);

	VertexOut out;
	out.position	= float4(position, 1.0);
	out.color	= color;

	return out;
}
