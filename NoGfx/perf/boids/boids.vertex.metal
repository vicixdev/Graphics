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

struct Args {
        device Boid* boids;
        device packed_float2* vertices;
};
static_assert(sizeof(Args) == 16, "");

constant uint width [[function_constant(0)]];
constant uint height [[function_constant(1)]];

[[host_name("main")]]
vertex VertexOut vertexMain(
		uint		vertexIndex	[[vertex_id]],
		uint		instanceId	[[instance_id]],
        device  const Args&     args            [[buffer(0)]]
) {
        Boid boid = args.boids[instanceId];

        float angle = atan2(boid.w, boid.z);
        float s = sin(angle);
        float c = cos(angle);

        float2 localPosition = args.vertices[vertexIndex].xy;
        float2 rotatedPosition = float2(
                localPosition.x * c - localPosition.y * s,
                localPosition.x * s + localPosition.y * c);

        float2 worldPosition = rotatedPosition + boid.xy;
        //float2 clipPosition = float2(
                //(worldPosition.x / as_type<float>(width)) * 2.0 - 1.0,
                //1.0 - (worldPosition.y / as_type<float>(height)) * 2.0);
        float2 clipPosition = float2(
                (worldPosition.x / 640.0) * 2.0 - 1.0,
                1.0 - (worldPosition.y / 480.0) * 2.0);


        VertexOut vertexOut;
        vertexOut.position = float4(clipPosition, 0.0, 1.0);
        return vertexOut;
}

