#include <metal_stdlib>

using namespace metal;

struct VertexIn {
	device packed_float3*	positions;
	device packed_float2*	uvs;
	float			direction;
};

struct VertexOut {
	float4 position [[position]];
	float2 uv;
};

[[host_name("main")]]
vertex VertexOut vertexMain(
		uint		vertexIndex	[[vertex_id]],
		uint		instanceId	[[instance_id]],
	device	const VertexIn&	vertexData	[[buffer(0)]]
) {
	float3 position	= float3(vertexData.positions[vertexIndex]);
	float2 uv	= float2(vertexData.uvs[vertexIndex]);

	position += float3(0.1, -0.1, 0.0) * instanceId * float3(cos(vertexData.direction), sin(vertexData.direction), 1.0f);

	VertexOut out;
	out.position	= float4(position, 1.0);
	out.uv		= uv;

	return out;
}
