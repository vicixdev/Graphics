#include <metal_stdlib>
using namespace metal;

typedef packed_float2 Vertex;

// boid[0] = x;
// boid[1] = y;
// boid[2] = dx;
// boid[3] = dy;
typedef float4 Boid;

struct VertexOut {
	float4 position [[position]];
};

constant float width [[function_constant(0)]];
constant float height [[function_constant(1)]];

vertex VertexOut vertexMain(
		uint		vertexIndex	[[vertex_id]],
		uint		instanceId	[[instance_id]],
	device	const Boid*	boids	        [[buffer(0)]],
        device  const Vertex*   vertices        [[buffer(1)]]
) {
        Boid boid = boids[instanceId];

        float angle = atan2(boid.w, boid.z);
        float s = sin(angle);
        float c = cos(angle);

        float2 localPosition = vertices[vertexIndex].xy;
        float2 rotatedPosition = float2(
                localPosition.x * c - localPosition.y * s,
                localPosition.x * s + localPosition.y * c);

        float2 worldPosition = rotatedPosition + boid.xy;
        float2 clipPosition = float2(
                (worldPosition.x / width) * 2.0 - 1.0,
                1.0 - (worldPosition.y / height) * 2.0);

        VertexOut vertexOut;
        vertexOut.position = float4(clipPosition, 0.0, 1.0);
        return vertexOut;
}

fragment float4 fragmentMain() {
        return float4(1.0, 1.0, 1.0, 0.0);
}
