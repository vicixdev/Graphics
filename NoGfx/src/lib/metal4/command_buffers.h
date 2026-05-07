#ifndef MTL4_COMMAND_BUFFERS_H
#define MTL4_COMMAND_BUFFERS_H

#include <lib/common/page.h>
#include <lib/common/static_handle_map.h>
#include <lib/metal4/pipelines.h>
#include <lib/metal4/queue.h>

#include <gpu/gpu.h>
#include <Metal/Metal.h>

#define MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS 16

struct Mtl4SemaphoreMetadata;

typedef CmnHandle Mtl4CommandBuffer;

typedef enum Mtl4CommandBufferStatus {
	MTL4_COMMAND_BUFFER_ENCODING,
	MTL4_COMMAND_BUFFER_SUBMITTED,
} Mtl4CommandBufferStatus;

// NOTE: Encoding a command encoder is not thread safe: It can happen from any thread, but sequential encoding
//	is expected. The synchronization is thus expected from the user.
typedef struct Mtl4CommandBufferMetadata {
	Mtl4CommandBufferStatus	status;

	id<MTL4CommandQueue>		queue;
	id<MTLSharedEvent>		submitEvent;
	id<MTL4CommandAllocator>	commandAllocator;

	id<MTL4CommandBuffer>		commandBuffer;
	id<MTL4ComputeCommandEncoder>	computeEncoder;
	id<MTL4RenderCommandEncoder>	renderEncoder;
} Mtl4CommandBufferMetadata;

typedef struct Mtl4CommandBufferStorage {
	id<MTLSharedEvent>		submitEvents[MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS];
	id<MTL4CommandAllocator>	commandAllocators[MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS];
	id<MTL4CommandQueue>		queues[MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS];

	// Atomic
	uint64_t submitCount;

	CmnStaticHandleMap<Mtl4CommandBufferMetadata, MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS> commandBuffers;
	CmnRWMutex	commandBuffersMutex;
} Mtl4CommandBufferStorage;
extern Mtl4CommandBufferStorage gMtl4CommandBufferStorage;

void mtl4InitCommandBufferStorage(GpuResult* result);
void mtl4FiniCommandBufferStorage(void);

GpuCommandBuffer mtl4StartCommandEncoding(GpuQueue queue, GpuResult* result);
void mtl4Submit(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result);
void mtl4SubmitWithSignal(
	GpuQueue queue,
	GpuCommandBuffer* commandBuffers,
	size_t commandBufferCount,
	GpuSemaphore semaphore,
	uint64_t value,
	GpuResult* result
);

void mtl4MemCpy(GpuCommandBuffer cb, void* destGpu, void* srcGpu, size_t size, GpuResult* result);
void mtl4CopyToTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result);
void mtl4CopyFromTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result);

void mtl4SetActiveTextureHeapPtr(GpuCommandBuffer cb, void *ptrGpu, GpuResult* result);

void mtl4Barrier(GpuCommandBuffer cb, GpuStage before, GpuStage after, GpuHazardFlags hazards, GpuResult* result);
void mtl4SignalAfter(GpuCommandBuffer cb, GpuStage before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result);
void mtl4WaitBefore(GpuCommandBuffer cb, GpuStage after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result);

bool mtl4AcquireResourcesForNewCommandBuffer(Mtl4CommandBuffer* handle, id<MTL4CommandQueue>* queue, id<MTL4CommandAllocator>* mtlAllocator, id<MTLSharedEvent>* submitEvent);
// NOTE: Requires deletion-lock on gMtl4CommandBufferStorage.sync.
void mtl4ReleaseCommandBufferResources(Mtl4CommandBuffer handle);
bool mtl4IsCommandBufferScheduledForDeletion(Mtl4CommandBuffer commandBuffer);

void mtl4EnsureValidCommandBuffer(Mtl4CommandBufferMetadata* metadata);
void mtl4EnsureValidComputeEndoderFor(Mtl4CommandBufferMetadata* metadata);
void mtl4FlushCommandEncoderOf(Mtl4CommandBufferMetadata* metadata);
void mtl4FlushCommandBuffer(Mtl4CommandBufferMetadata* metadata);
void mtl4SubmitSingleBuffer(GpuQueue queue, GpuCommandBuffer commandBuffer, id<MTLSharedEvent> event, uint64_t value, GpuResult* result);
void mtl4StartCommandBufferExecution(Mtl4CommandBufferMetadata* metadata);

bool mtl4IsStageCompute(GpuStage stage);
bool mtl4IsStageRender(GpuStage stage);

MTLStages mtl4GpuToMtlStage(GpuStage stage);
MTLStages mtl4GpuToMtlComputeStage(GpuStage stage);
MTLStages mtl4GpuToMtlFragmentStage(GpuStage stage);
MTL4VisibilityOptions mtl4GpuHazardsToMtlVisibilityOptions(GpuHazardFlags hazards);

Mtl4CommandBufferMetadata* mtl4AcquireCommandBufferMetadataFrom(Mtl4CommandBuffer handle);

inline Mtl4CommandBuffer mtl4GpuCommandBufferToHandle(GpuCommandBuffer commandBuffer) {
	return *(Mtl4CommandBuffer*)&commandBuffer;
}
inline GpuCommandBuffer mtl4HandleToGpuCommandBuffer(Mtl4CommandBuffer handle) {
	return *(GpuCommandBuffer*)&handle;
}

#endif // MTL4_COMMAND_BUFFERS_H

