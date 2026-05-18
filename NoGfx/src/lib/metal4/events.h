#ifndef MTL4_FENCES_H
#define MTL4_FENCES_H

#include <gpu/gpu.h>

#include <lib/common/page.h>
#include <lib/common/hash_map.h>
#include <lib/common/pointer_map.h>
#include <lib/common/storage_sync.h>

#include <Metal/Metal.h>

struct Mtl4CommandBufferMetadata;

typedef struct Mtl4EventStorage {
	CmnPage		page;
	CmnArena	arena;

	CmnPointerMap	<id<MTLEvent>>	lookup;
	CmnStorageSync	sync;
} Mtl4EventStorage;
extern Mtl4EventStorage gMtl4EventStorage;

void mtl4InitEventStorage(GpuResult* result);
void mtl4FiniEventStorage(void);

id<MTLEvent> mtl4AcquireEventOf(void* gpuPtr);
id<MTLEvent> mtl4AcquireOrCreateEventFor(void* gpuPtr, GpuResult* result);
void mtl4ReleaseEvent(void);

#endif // MTL4_FENCES_H

