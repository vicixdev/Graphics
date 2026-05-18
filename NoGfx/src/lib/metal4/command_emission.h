#ifndef MTL4_ENCODING_CONTEXT_H
#define MTL4_ENCODING_CONTEXT_H

#include <lib/metal4/command.h>
#include <lib/metal4/semaphores.h>
#include <lib/metal4/command_emitters.h>

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

