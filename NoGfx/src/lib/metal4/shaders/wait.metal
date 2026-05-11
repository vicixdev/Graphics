#include <metal_stdlib>
#include <metal_atomic>

using namespace metal;

enum GpuOp : uint32_t {
	GPU_OP_NEVER = 0,
	GPU_OP_LESS,
	GPU_OP_EQUAL,
	GPU_OP_LESS_EQUAL,
	GPU_OP_GREATER,
	GPU_OP_NOT_EQUAL,
	GPU_OP_GREATER_EQUAL,
	GPU_OP_ALWAYS,
};

struct Mtl4WaitOperation {
	uintptr_t	address;
	uint64_t	mask;
	uint64_t	value;
};

constant ulong waitOp [[function_constant(0)]];

[[host_name("main")]]
kernel void mtl4WaitFor(
	device	Mtl4WaitOperation&	wait		[[buffer(0)]],
		uint			threadId	[[thread_position_in_grid]]
) {
	if (threadId != 0) {
		return;
	}

	device atomic_uint* address = (device atomic_uint*)wait.address;
	uint mask = (uint)wait.mask;
	uint value = (uint)wait.value;

	for (;;) {
		atomic_thread_fence(mem_flags::mem_device, memory_order_seq_cst);

 		uint32_t currentValue = atomic_load_explicit(address, memory_order_relaxed);
		currentValue &= mask;

		switch ((GpuOp)waitOp) {
			case GPU_OP_NEVER: {
				break;
			}
			case GPU_OP_LESS: {
				if (currentValue < value) {
					return;
				}
				break;
			}
			case GPU_OP_EQUAL: {
				if (currentValue == value) {
					return;
				}
				break;
			}
			case GPU_OP_LESS_EQUAL: {
				if (currentValue <= value) {
					return;
				}
				break;
			}
			case GPU_OP_GREATER: {
				if (currentValue > value) {
					return;
				}
				break;
			}
			case GPU_OP_NOT_EQUAL: {
				if (currentValue != value) {
					return;
				}
				break;
			}
			case GPU_OP_GREATER_EQUAL: {
				if (currentValue >= value) {
					return;
				}
				break;
			}
			case GPU_OP_ALWAYS: {
				return;
			}
		}
	}
}

