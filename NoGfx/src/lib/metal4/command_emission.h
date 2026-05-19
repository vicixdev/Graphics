#ifndef MTL4_ENCODING_CONTEXT_H
#define MTL4_ENCODING_CONTEXT_H

#include <lib/metal4/command.h>
#include <lib/metal4/semaphores.h>

struct Mtl4QueueMetadata;

typedef struct Mtl4CommandEmissionContext {
	// Atomic
	bool				inUse;

	id<MTL4CommandQueue>		queue;
	id<MTL4CommandAllocator>	commandAllocator;

	id<MTL4CommandBuffer>		commandBuffer;
	id<MTL4ComputeCommandEncoder>	computeEncoder;
	id<MTL4RenderCommandEncoder>	renderEncoder;

	id<MTL4ArgumentTable>		computeArgumentTable;
	id<MTL4ArgumentTable>		vertexArgumentTable;
	id<MTL4ArgumentTable>		fragmentArgumentTable;

	id<MTLIndirectCommandBuffer>	icbBuffer;
	// Contains an uint.
	id<MTLBuffer>			firstFreeIcbIndex;

	id<MTLBuffer>			bumpBuffer;
	size_t				bumpBufferOffset;
	size_t				bumpBufferSize;

	MTLStages			computeUsedStages;
} Mtl4CommandEmissionContext;

void mtl4InitCommandEmissionContext(Mtl4CommandEmissionContext* context, Mtl4QueueMetadata* queue, GpuResult* result);
void mtl4FiniCommandEmissionContext(Mtl4CommandEmissionContext* context);

MTLStages mtl4GpuToMtlStage(GpuStageFlags stage);
MTL4VisibilityOptions mtl4GpuHazardsToMtlVisibilityOptions(GpuHazardFlags hazards);

void mtl4FlushComputeEncoder(Mtl4CommandEmissionContext* context);
void mtl4FlushCommandBuffer(Mtl4CommandEmissionContext* context);
void mtl4EnsureValidCommandBuffer(Mtl4CommandEmissionContext* context);
void mtl4EnsureValidComputeEncoder(Mtl4CommandEmissionContext* context);

size_t mtl4BumpAllocIn(Mtl4CommandEmissionContext* context, size_t size);

void mtl4EmitBarrierForComputeStage(Mtl4CommandEmissionContext* context, GpuStageFlags before, MTLStages stage, GpuHazardFlags hazards);
void mtl4EmitBlitBarrier(Mtl4CommandEmissionContext* context, GpuStageFlags before, GpuHazardFlags hazards);
void mtl4EmitDispatchBarrier(Mtl4CommandEmissionContext* context, GpuStageFlags before, GpuHazardFlags hazards);
void mtl4EmitRenderpassBarriers(Mtl4CommandEmissionContext* context, Mtl4Command* command);
void mtl4EmitRenderpassBarriersForIndirectPrep(Mtl4CommandEmissionContext* context, Mtl4Command* command);

void mtl4EmitCopyBufferToBuffer(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result);
void mtl4EmitCopyBufferToTexture(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result);
void mtl4EmitCopyTextureToBuffer(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result);

void mtl4EmitDispatch(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result);
void mtl4EmitDispatchIndirect(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result);

void mtl4EmitSignal(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result);
void mtl4EmitWait(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result);

void mtl4EmitDrawIndirectPrep(Mtl4CommandEmissionContext* context, Mtl4RenderCommand* command, GpuResult* result);
void mtl4EmitMultiDrawIndirectPrep(Mtl4CommandEmissionContext* context, Mtl4RenderCommand* command, GpuResult* result);
void mtl4EmitRenderpassPrep(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result);
MTLPrimitiveType mtl4EmitDrawSetup(Mtl4CommandEmissionContext* context, Mtl4RenderCommand* command, GpuResult* result);

void mtl4EmitBeginRenderpass(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result);
void mtl4EmitDraw(Mtl4CommandEmissionContext* context, Mtl4RenderCommand* command, GpuResult* result);
void mtl4EmitDrawIndirect(Mtl4CommandEmissionContext* context, Mtl4RenderCommand* command, GpuResult* result);
void mtl4EmitMultiDrawIndirect(Mtl4CommandEmissionContext* context, Mtl4RenderCommand* command, GpuResult* result);
void mtl4EmitRenderpass(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result);

void mtl4EmitCommand(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result);
void mtl4EmitSemaphoreSignal(
	Mtl4CommandEmissionContext* context,
	Mtl4Semaphore semaphore,
	uint64_t value,
	GpuResult* result
);

#endif // MTL4_ENCODING_CONTEXT_H

