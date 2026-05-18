#ifndef MTL4_COMMAND_BUFFERS_H
#define MTL4_COMMAND_BUFFERS_H

#include <lib/common/page.h>
#include <lib/common/static_handle_map.h>
#include <lib/metal4/textures.h>
#include <lib/metal4/pipelines.h>
#include <lib/metal4/queue.h>
#include <lib/metal4/depthstencilstates.h>
#include <lib/metal4/blend_states.h>
#include <lib/metal4/encoding_context.h>

#include <gpu/gpu.h>
#include <Metal/Metal.h>

#define MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS 4

struct Mtl4SemaphoreMetadata;

typedef CmnHandle Mtl4CommandBuffer;

typedef enum Mtl4CommandBufferStatus {
	MTL4_COMMAND_BUFFER_ENCODING,
	MTL4_COMMAND_BUFFER_SUBMITTED,
} Mtl4CommandBufferStatus;

typedef struct Mtl4RecordedBarrier {
	GpuStageFlags	before;
	GpuHazardFlags	hazards;
} Mtl4RecordedBarrier;
#define MTL4_GPU_STAGES_COUNT 6


// NOTE: Encoding a command encoder is not thread safe: It can happen from any thread, but sequential encoding
//	is expected. The synchronization is thus expected from the user.
typedef struct Mtl4CommandBufferMetadata {
	Mtl4CommandBufferStatus	status;

	CmnAllocator			allocator;

	Mtl4Pipeline			pipeline;
	Mtl4DepthStencilState		depthStencil;
	Mtl4BlendState			blend;
	void*				textureHeapPtr;

	Mtl4RecordedBarrier		barriersForQueueState[MTL4_GPU_STAGES_COUNT];

	bool				isEncodingRenderpass;
	Mtl4Command			activeRenderPass;
	
	CmnExponentialArray	<Mtl4Command, 5>	commands;
} Mtl4CommandBufferMetadata;

typedef struct Mtl4CommandBufferStorage {
	CmnPage				pages			[MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS];
	CmnArena			arenas			[MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS];

	Mtl4CommandEmissionContext	emissionContexts	[MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS];
	// Atomic
	size_t				emissionContextIdx;

	id<MTLBuffer>			zeroBuffer;
	Mtl4Pipeline			prepareMultiDrawIcbsPipeline;

	// Atomic
	uint64_t submitCount;

	CmnStaticHandleMap<Mtl4CommandBufferMetadata, MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS> commandBuffers;
	CmnRWMutex	commandBuffersMutex;
} Mtl4CommandBufferStorage;
extern Mtl4CommandBufferStorage gMtl4CommandBufferStorage;

void mtl4InitCommandBufferStorage(GpuResult* result);
void mtl4FiniCommandBufferStorage(void);

GpuCommandBuffer mtl4StartCommandEncoding(GpuQueue queue, GpuResult* result);

void mtl4Submit(Mtl4CommandEmissionContext* emitContext, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result);
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
void mtl4DrawIndexedInstancedIndirect(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, void* argsGpu, GpuResult* result);
void mtl4DrawIndexedInstancedIndirectMulti(GpuCommandBuffer cb, void* dataVxGpu, uint32_t vxStride, void* dataPxGpu, uint32_t pxStride, void* argsGpu, void* drawCountGpu, GpuResult* result);

void mtl4FlushBarriers(Mtl4CommandBufferMetadata* metadata);
void mtl4GetBarrierFor(Mtl4CommandBufferMetadata* metadata, GpuStage after, GpuStageFlags* before, GpuHazardFlags* hazards);
void mtl4AddBarrierFor(Mtl4CommandBufferMetadata* metadata, GpuStage after, GpuStageFlags before, GpuHazardFlags hazards);

GpuRenderPassDesc* mtl4CopyRenderPassDesc(Mtl4CommandBufferMetadata* metadata, const GpuRenderPassDesc* desc, GpuResult* result);

Mtl4CommandBufferMetadata* mtl4AcquireCommandBufferMetadataFrom(Mtl4CommandBuffer handle);

Mtl4CommandEmissionContext* mtl4AcquireEmissionContext(void);
void mtl4ReleaseEmissionContext(Mtl4CommandEmissionContext* context);

inline Mtl4CommandBuffer mtl4GpuCommandBufferToHandle(GpuCommandBuffer commandBuffer) {
	return *(Mtl4CommandBuffer*)&commandBuffer;
}
inline GpuCommandBuffer mtl4HandleToGpuCommandBuffer(Mtl4CommandBuffer handle) {
	return *(GpuCommandBuffer*)&handle;
}

#endif // MTL4_COMMAND_BUFFERS_H

