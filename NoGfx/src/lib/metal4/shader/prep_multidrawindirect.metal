#include <metal_stdlib>
using namespace metal;

struct GpuMultiDrawIndirectArgs {
	device uint*	indices;
	uint		indexCount;
	uint		instanceCount;
};
static_assert(sizeof(GpuMultiDrawIndirectArgs) == 16);

struct PrepareIcbArgs {
	command_buffer				commandBuffer;

	device void*				textureHeap;
	device void*				fragmentData;
	device void*				vertexData;
	device GpuMultiDrawIndirectArgs*	args;
	device uint*				argCount;

	device MTLIndirectCommandBufferExecutionRange*	outRange;

	size_t					icbStartOffset;
	size_t					vertexStride;
	size_t					fragmentStride;

	primitive_type				primitive;
};
static_assert(sizeof(PrepareIcbArgs) == 88, "Unexpected size");

[[host_name("main")]]
kernel void prepareMultiDrawIndirectIcbs(
		uint	threadId	[[thread_position_in_grid]],
	device	void*	argsVoid	[[buffer(0)]]
) {
	
	device PrepareIcbArgs* args = (device PrepareIcbArgs*)argsVoid;
	
	args->outRange->location = args->icbStartOffset;
	args->outRange->length = *args->argCount;

	render_command command(args->commandBuffer, threadId + args->icbStartOffset);
	command.reset();

	if (threadId >= *args->argCount) {
		return;
	}
	
	if (args->vertexData != nullptr) {
		command.set_vertex_buffer((device void*)((uintptr_t)args->vertexData + (args->vertexStride * threadId)), 0);
	}
	if (args->fragmentData != nullptr) {
		command.set_fragment_buffer((device void*)((uintptr_t)args->fragmentData + (args->fragmentStride * threadId)), 0);
	}
	command.set_fragment_buffer(args->textureHeap, 1);
	
	// command.set_barrier();
	command.draw_indexed_primitives(
		args->primitive,
		args->args[threadId].indexCount,
		args->args[threadId].indices,
		args->args[threadId].instanceCount
	);
}


