#ifndef MTL4_COMMAND_EMITTER_STORAGE_H
#define MTL4_COMMAND_EMITTER_STORAGE_H

#define MTL4_MAX_COMMAND_EMITTERS 4

#include <lib/common/semaphore.h>
#include <lib/metal4/queue.h>
#include <lib/metal4/pipelines.h>

typedef struct Mtl4CommandEmissionContext {
	// Atomic
	bool				inUse;

	Mtl4QueueMetadata*		queueMetadata;
	id<MTL4CommandAllocator>	commandAllocator;

	id<MTL4CommandBuffer>		commandBuffer;
	id<MTL4ComputeCommandEncoder>	computeEncoder;
	id<MTL4RenderCommandEncoder>	renderEncoder;

	id<MTL4ArgumentTable>		computeArgumentTable;
	id<MTL4ArgumentTable>		vertexArgumentTable;
	id<MTL4ArgumentTable>		fragmentArgumentTable;

	id<MTLBuffer>			bumpBuffer;
	size_t				bumpBufferOffset;
	size_t				bumpBufferSize;

	MTLStages			computeUsedStages;
} Mtl4CommandEmissionContext;

typedef struct Mtl4CommandEmissionStorage {
	Mtl4CommandEmissionContext	contexts	[MTL4_MAX_COMMAND_EMITTERS];
	// Atomic
	size_t				firstFreeContextIndex;
	// NOTE: Allows at max MTL4_MAX_COMMAND_EMITTER context users.
	CmnSemaphore			contextsSemaphore;


	id<MTLBuffer>			zeroBuffer;

	id<MTLIndirectCommandBuffer>	icbBuffer;
	// Contains an atomic_uint.
	id<MTLBuffer>			firstFreeIcbIndex;

	// Instance of shader/acquire_icb_range.metal.
	Mtl4Pipeline acquireIcbRange;
	// Instance of shader/prep_multidrawindirect.metal.
	Mtl4Pipeline prepareMultidrawIcbs;
} Mtl4CommandEmissionStorage;
extern Mtl4CommandEmissionStorage gMtl4CommandEmissionStorage;

void mtl4InitCommandEmissionStorage(GpuResult* result);
void mtl4FiniCommandEmissionStorage(void);

void mtl4InitCommandEmissionContext(Mtl4CommandEmissionContext* context, GpuResult* result);
void mtl4FiniCommandEmissionContext(Mtl4CommandEmissionContext* context);

Mtl4CommandEmissionContext* mtl4AcquireCommandEmissionContext(Mtl4Queue queue);
void mtl4ReleaseCommandEmissionContext(Mtl4CommandEmissionContext* context);

#endif // MTL4_COMMAND_EMITTER_STORAGE_H

