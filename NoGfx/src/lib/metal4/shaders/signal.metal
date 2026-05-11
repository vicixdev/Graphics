#include <metal_stdlib>
#include <metal_atomic>

using namespace metal;

enum GpuSignal : uint32_t {
	GPU_SIGNAL_ATOMIC_SET = 0,
	GPU_SIGNAL_ATOMIC_MAX,
	GPU_SIGNAL_ATOMIC_OR,
};

struct Mtl4SignalOperation {
	uintptr_t	address;
	uint64_t	value;
};

constant ulong signalOp [[function_constant(0)]];

[[host_name("main")]]
kernel void mtl4Signal(
	device Mtl4SignalOperation&	signal		[[buffer(0)]],
		uint			threadId	[[thread_position_in_grid]]
) {
	if (threadId != 0) {
		return;
	}

	device atomic_uint* address = (device atomic_uint*)signal.address;
	uint value = (uint)signal.value;

	atomic_thread_fence(mem_flags::mem_device, memory_order_seq_cst);

	switch ((GpuSignal)signalOp) {
		case GPU_SIGNAL_ATOMIC_SET: {
			atomic_store_explicit(address, value, memory_order_relaxed);
			break;
		}
		case GPU_SIGNAL_ATOMIC_OR: {
			atomic_fetch_or_explicit(address, value, memory_order_relaxed);
			break;
		}
		case GPU_SIGNAL_ATOMIC_MAX: {
			atomic_fetch_max_explicit(address, value, memory_order_relaxed);
			break;
		}
	}

	atomic_thread_fence(mem_flags::mem_device, memory_order_seq_cst);
}

