#include <metal_stdlib>
using namespace metal;

struct AcquireIcbRangeArgs {
	device	MTLIndirectCommandBufferExecutionRange*	outRange;

	device	uint*					requiredLength;
	device	uint*					firstFreeIdx;
};

constant uint icbSize [[function_constant(0)]];

[[host_name("main")]]
void kernel acquireIcbRange(
		uint			threadId	[[thread_position_in_grid]],
	device	AcquireIcbRangeArgs*	args		[[buffer(0)]]
) {
	if (threadId != 0) {
		return;
	}

	uint requiredLength = min(*args->requiredLength, (uint)512);

	uint start = *args->firstFreeIdx;
	uint newStart = start + requiredLength;
	if (newStart >= icbSize) {
		newStart = 0;
	}

	*args->firstFreeIdx = newStart;

	args->outRange->location = start;
	args->outRange->length = requiredLength;
}

