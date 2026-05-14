#include <metal_stdlib>

using namespace metal;

constant uint vertexScale [[function_constant(0)]];

struct VertexOut {
	float4 position [[position]];
};

[[host_name("main")]] vertex VertexOut vertexMain(uint vertexId [[vertex_id]]) {
	VertexOut out;
	out.position = float4(float(vertexId) * as_type<float>(vertexScale), 0.0, 0.0, 1.0);
	return out;
}
