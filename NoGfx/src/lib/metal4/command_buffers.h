#ifndef MTL4_COMMAND_BUFFERS_H
#define MTL4_COMMAND_BUFFERS_H

#include <lib/common/page.h>
#include <lib/common/static_handle_map.h>
#include <lib/metal4/pipelines.h>
#include <lib/metal4/queue.h>
#include <lib/metal4/depthstencilstates.h>
#include <lib/metal4/blend_states.h>

#include <gpu/gpu.h>
#include <Metal/Metal.h>

#define MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS 16

struct Mtl4SemaphoreMetadata;

typedef CmnHandle Mtl4CommandBuffer;

typedef enum Mtl4CommandBufferStatus {
	MTL4_COMMAND_BUFFER_ENCODING,
	MTL4_COMMAND_BUFFER_SUBMITTED,
} Mtl4CommandBufferStatus;

typedef struct Mtl4RecordedBarrier {
	GpuStageFlags	after;
	GpuHazardFlags	hazards;
} Mtl4RecordedBarrier;
#define MTL4_GPU_STAGES_COUNT 5

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

	id<MTL4ArgumentTable>		computeArgumentTable;
	id<MTL4ArgumentTable>		vertexArgumentTable;
	id<MTL4ArgumentTable>		fragmentArgumentTable;

	Mtl4Pipeline			pipeline;
	Mtl4DepthStencilState		depthStencil;
	Mtl4BlendState			blend;
	void*				textureHeapPtr;

	Mtl4RecordedBarrier		renderBarrierForQueueState[MTL4_GPU_STAGES_COUNT];
} Mtl4CommandBufferMetadata;

typedef struct Mtl4CommandBufferStorage {
	id<MTLSharedEvent>		submitEvents		[MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS];
	id<MTL4CommandAllocator>	commandAllocators	[MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS];
	id<MTL4CommandQueue>		queues			[MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS];
	id<MTL4ArgumentTable>		computeArgumentTables	[MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS];
	id<MTL4ArgumentTable>		vertexArgumentTables	[MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS];
	id<MTL4ArgumentTable>		fragmentArgumentTables	[MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS];

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

void mtl4SetPipeline(GpuCommandBuffer cb, GpuPipeline pipeline, GpuResult* result);
void mtl4SetActiveTextureHeapPtr(GpuCommandBuffer cb, void *ptrGpu, GpuResult* result);
void mtl4SetDepthStencilState(GpuCommandBuffer cb, GpuDepthStencilState state, GpuResult* result);
void mtl4SetBlendState(GpuCommandBuffer cb, GpuBlendState state, GpuResult* result);

void mtl4Barrier(GpuCommandBuffer cb, GpuStageFlags before, GpuStageFlags after, GpuHazardFlags hazards, GpuResult* result);
void mtl4SignalAfter(GpuCommandBuffer cb, GpuStageFlags before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result);
void mtl4WaitBefore(GpuCommandBuffer cb, GpuStageFlags after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result);

void mtl4Dispatch(GpuCommandBuffer cb, void* dataGpu, uint32_t gridDimensions[3], GpuResult* result);
void mtl4DispatchIndirect(GpuCommandBuffer cb, void* dataGpu, void* gridDimensionsGpu, GpuResult* result);

void mtl4BeginRenderPass(GpuCommandBuffer cb, const GpuRenderPassDesc* desc, GpuResult* result);
void mtl4EndRenderPass(GpuCommandBuffer cb, GpuResult* result);

void mtl4DrawIndexedInstanced(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, uint32_t indexCount, uint32_t instanceCount, GpuResult* result);

bool mtl4AcquireResourcesForNewCommandBuffer(
	Mtl4CommandBuffer* handle,
	id<MTL4CommandQueue>* queue,
	id<MTL4CommandAllocator>* mtlAllocator,
	id<MTL4ArgumentTable>* computeArgumentTable,
	id<MTL4ArgumentTable>* vertexArgumentTable,
	id<MTL4ArgumentTable>* fragmentArgumentTable,
	id<MTLSharedEvent>* submitEvent
);
// NOTE: Requires deletion-lock on gMtl4CommandBufferStorage.sync.
void mtl4ReleaseCommandBufferResources(Mtl4CommandBuffer handle);
bool mtl4IsCommandBufferScheduledForDeletion(Mtl4CommandBuffer commandBuffer);

void mtl4PushDebugLabel(Mtl4CommandBufferMetadata* metadata, const char* label);
void mtl4PopDebugLabel(Mtl4CommandBufferMetadata* metadata);

void mtl4EnsureValidCommandBuffer(Mtl4CommandBufferMetadata* metadata);
void mtl4EnsureValidComputeEndoderFor(Mtl4CommandBufferMetadata* metadata);
void mtl4FlushCommandEncoderOf(Mtl4CommandBufferMetadata* metadata);
void mtl4FlushCommandBuffer(Mtl4CommandBufferMetadata* metadata);
void mtl4SubmitSingleBuffer(GpuQueue queue, GpuCommandBuffer commandBuffer, id<MTLSharedEvent> event, uint64_t value, GpuResult* result);
void mtl4StartCommandBufferExecution(Mtl4CommandBufferMetadata* metadata);

bool mtl4IsStageCompute(GpuStageFlags stage);
bool mtl4IsStageRender(GpuStageFlags stage);

MTLStages mtl4GpuToMtlStage(GpuStageFlags stage);
MTLStages mtl4GpuToMtlComputeStage(GpuStageFlags stage);
MTLStages mtl4GpuToMtlFragmentStage(GpuStageFlags stage);
MTL4VisibilityOptions mtl4GpuHazardsToMtlVisibilityOptions(GpuHazardFlags hazards);

Mtl4CommandBufferMetadata* mtl4AcquireCommandBufferMetadataFrom(Mtl4CommandBuffer handle);

inline Mtl4CommandBuffer mtl4GpuCommandBufferToHandle(GpuCommandBuffer commandBuffer) {
	return *(Mtl4CommandBuffer*)&commandBuffer;
}
inline GpuCommandBuffer mtl4HandleToGpuCommandBuffer(Mtl4CommandBuffer handle) {
	return *(GpuCommandBuffer*)&handle;
}

#endif // MTL4_COMMAND_BUFFERS_H

