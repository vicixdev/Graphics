#include <metal_stdlib>
using namespace metal;

struct AcquireIcbRangeArgs {
	device	MTLIndirectCommandBufferExecutionRange*	outRange;

	device	uint*					requiredLength;
	device	atomic_uint*				firstFreeIdx;
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

	uint requiredLength = min(*args->requiredLength, (uint)16384);

	uint start;

	for (;;) {
		atomic_thread_fence(mem_flags::mem_device, memory_order_seq_cst);

		start = atomic_load_explicit(args->firstFreeIdx, memory_order_relaxed);

		uint newStart = start + requiredLength;
		if (newStart >= icbSize) {
			newStart = 0;
		}

		if (atomic_compare_exchange_weak_explicit(
			args->firstFreeIdx,
			&start,
			newStart,
			memory_order_relaxed,
			memory_order_relaxed
		)) {
			break;
		}
	}

	args->outRange->location = start;
	args->outRange->length = *args->requiredLength;
}

