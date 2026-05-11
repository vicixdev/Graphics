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
	uint64_t*	signaledValuesUploadBuffer;
	void*		signaledValuesGpuBuffer;
	size_t		uploadBufferSize;
	size_t		uploadBufferUsed;

	GpuPipeline	waitPipelines[GPU_OP_ALWAYS + 1];
	GpuPipeline	signalPipelines[GPU_SIGNAL_ATOMIC_OR + 1];
} Mtl4EventStorage;
extern Mtl4EventStorage gMtl4EventStorage;

void mtl4InitEventStorage(GpuResult* result);
void mtl4FiniEventStorage(void);

void mtl4SignalEvent(
	GpuCommandBuffer commandBuffer,
	GpuStage after,
	GpuSignal signal,
	void* gpuPtr,
	uint64_t value,
	GpuResult* result
);
void mtl4WaitEvent(
	GpuCommandBuffer commandBuffer,
	GpuStage before,
	GpuOp waitOp,
	void* gpuPtr,
	uint64_t value,
	uint64_t mask,
	GpuResult* result
);

#endif // MTL4_FENCES_H

