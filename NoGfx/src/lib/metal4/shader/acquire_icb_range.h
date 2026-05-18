#ifndef MTL4_ACQUIREICBRANGE_H
#define MTL4_ACQUIREICBRANGE_H

#include <lib/common/common.h>
#include <lib/metal4/shader/acquire_icb_range.metal.h>

typedef struct Mtl4AcquireIcbRangeArgs {
	// GpuPtr to MTLIndirectCommandBufferExecutionRange
	uintptr_t	outRange;

	// GpuPtr to uint32_t
	uintptr_t	requiredLength;
	// GpuPtr to atomic_uint
	uintptr_t	firstFreeIdx;
} Mtl4AcquireIcbRangeArgs;

#endif // MTL4_ACQUIREICBRANGE_H

