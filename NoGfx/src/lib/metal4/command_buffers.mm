#include "command_buffers.h"

#include <lib/common/heap_allocator.h>
#include <lib/common/atomic.h>
#include <lib/common/futex.h>
#include <lib/common/scoped_nsautoreleasepool.h>
#include <lib/metal4/context.h>
#include <lib/metal4/tables.h>
#include <lib/metal4/allocation.h>
#include <lib/metal4/events.h>
#include <lib/metal4/semaphores.h>
#include <lib/metal4/command_emission.h>
#include <lib/metal4/shader/prep_multidrawindirect.h>

Mtl4CommandBufferStorage gMtl4CommandBufferStorage;

void mtl4InitCommandBufferStorage(GpuResult* result) {

	CmnResult localResult;

	gMtl4CommandBufferStorage = {};

	cmnCreateStaticHandleMap(&gMtl4CommandBufferStorage.commandBuffers, {});

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		gMtl4CommandBufferStorage.pages[i] = cmnCreatePage(1024 * 1024 * 32, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
		if (localResult != CMN_SUCCESS) {
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return;
		}

		gMtl4CommandBufferStorage.arenas[i] = cmnPageToArena(gMtl4CommandBufferStorage.pages[i]);
	}


	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4FiniCommandBufferStorage(void) {
	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		cmnDestroyPage(gMtl4CommandBufferStorage.pages[i]);
	}

	gMtl4CommandBufferStorage = {};
	return;
}

GpuCommandBuffer mtl4StartCommandEncoding(GpuQueue queue, GpuResult* result) {
	(void)queue;

	CmnResult localResult;

	Mtl4CommandBuffer handle;
	{
		CmnScopedWriteRWMutex guard(&gMtl4CommandBufferStorage.commandBuffersMutex);
		handle = cmnInsert(&gMtl4CommandBufferStorage.commandBuffers, {}, &localResult);
	}

	if (localResult != CMN_SUCCESS) {
		// NOTE: If this occurs, we are out of resource slots.
		CMN_SET_RESULT(result, GPU_TOO_MANY_UNSUBMITTED_COMMAND_BUFFERS);
		return false;
	}

	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	metadata->status = MTL4_COMMAND_BUFFER_ENCODING;
	metadata->allocator = cmnArenaAllocator(&gMtl4CommandBufferStorage.arenas[handle.index]);

	cmnFreeAll(metadata->allocator);
	cmnCreateExponentialArray(&metadata->commands, metadata->allocator, &localResult);
	assert(localResult == CMN_SUCCESS);

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return mtl4HandleToGpuCommandBuffer(handle);
}

void mtl4Submit(Mtl4CommandEmissionContext* emitContext, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result) {
	bool didFindAllCommandBuffers = true;
	GpuResult lastCommandBufferError = GPU_SUCCESS;

	GpuResult localResult;
	for (size_t i = 0; i < commandBufferCount; i++) {
		Mtl4CommandBuffer commandBufferHandle = mtl4GpuCommandBufferToHandle(commandBuffers[i]);
		Mtl4CommandBufferMetadata* commandBuffer = mtl4AcquireCommandBufferMetadataFrom(commandBufferHandle);
		if (commandBuffer == nullptr) {
			didFindAllCommandBuffers = false;
			return;
		}

		for (size_t j = 0; j < commandBuffer->commands.length; j++) {
			mtl4EmitCommand(emitContext, &commandBuffer->commands[j], &localResult);
			if (localResult != GPU_SUCCESS) {
				lastCommandBufferError = localResult;
			}
		}
	}

	mtl4FlushCommandBuffer(emitContext);

	if (lastCommandBufferError == GPU_SUCCESS && !didFindAllCommandBuffers) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
	} else if (lastCommandBufferError != GPU_SUCCESS) {
		CMN_SET_RESULT(result, lastCommandBufferError);
	} else {
		CMN_SET_RESULT(result, GPU_SUCCESS);
	}
}

void mtl4Submit(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result) {
	(void)queue;

	CmnScopedNSAutoreleasePool pool;

	Mtl4CommandEmissionContext* emitContext = mtl4AcquireCommandEmissionContext({});
	defer (mtl4ReleaseCommandEmissionContext(emitContext));

	mtl4Submit(emitContext, commandBuffers, commandBufferCount, result);
}

void mtl4SubmitWithSignal(
	GpuQueue queue,
	GpuCommandBuffer* commandBuffers,
	size_t commandBufferCount,
	GpuSemaphore semaphore,
	uint64_t value,
	GpuResult* result
) {
	(void)queue;

	CmnScopedNSAutoreleasePool pool;

	Mtl4CommandEmissionContext* emitContext = mtl4AcquireCommandEmissionContext({});
	defer (mtl4ReleaseCommandEmissionContext(emitContext));

	mtl4Submit(emitContext, commandBuffers, commandBufferCount, result);
	mtl4EmitSemaphoreSignal(emitContext, mtl4GpuSemaphoreToHandle(semaphore), value, result);
}

void mtl4MemCpy(GpuCommandBuffer cb, void* destGpu, void* srcGpu, size_t size, GpuResult* result) {

	CmnResult localResult;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4Command command = {};
	command.type = MTL4_CMD_COPY_BUFFER_TO_BUFFER;
	command.copyBufferToBuffer.destination = destGpu;
	command.copyBufferToBuffer.source = srcGpu;
	command.copyBufferToBuffer.size = size;

	mtl4GetBarrierFor(metadata, GPU_STAGE_TRANSFER, &command.barrier.stages, &command.barrier.hazards);

	cmnAppend(&metadata->commands, command, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4CopyToTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result) {

	CmnResult localResult;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4Command command = {};
	command.type = MTL4_CMD_COPY_BUFFER_TO_TEXTURE;
	command.copyBufferToTexture.source = srcGpu;
	command.copyBufferToTexture.destinationTexture = mtl4GpuTextureToHadle(texture);
	command.copyBufferToTexture.destinationPtr = destGpu;

	mtl4GetBarrierFor(metadata, GPU_STAGE_TRANSFER, &command.barrier.stages, &command.barrier.hazards);

	cmnAppend(&metadata->commands, command, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4CopyFromTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result) {

	CmnResult localResult;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4Command command = {};
	command.type = MTL4_CMD_COPY_TEXTURE_TO_BUFFER;
	command.copyTextureToBuffer.sourcePtr = srcGpu;
	command.copyTextureToBuffer.sourceTexture = mtl4GpuTextureToHadle(texture);
	command.copyTextureToBuffer.destination = destGpu;

	mtl4GetBarrierFor(metadata, GPU_STAGE_TRANSFER, &command.barrier.stages, &command.barrier.hazards);

	cmnAppend(&metadata->commands, command, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
	
}

void mtl4Barrier(GpuCommandBuffer cb, GpuStageFlags before, GpuStageFlags after, GpuHazardFlags hazards, GpuResult* result) {
	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	for (size_t i = 0; i < MTL4_GPU_STAGES_COUNT; i++) {
		GpuStage select = (GpuStage)(1 << i);
		GpuStage stage = (GpuStage)(after & select);

		if (stage == 0) {
			continue;
		}

		mtl4AddBarrierFor(metadata, stage, before, hazards);
	}
}
void mtl4SetPipeline(GpuCommandBuffer cb, GpuPipeline pipeline, GpuResult* result) {
	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	metadata->pipeline = mtl4GpuPipelineToHandle(pipeline);
}

void mtl4SetActiveTextureHeapPtr(GpuCommandBuffer cb, void *ptrGpu, GpuResult* result) {
	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}
	
	metadata->textureHeapPtr = ptrGpu;
}

void mtl4SetDepthStencilState(GpuCommandBuffer cb, GpuDepthStencilState state, GpuResult* result) {
	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}
	
	metadata->depthStencil = mtl4GpuDepthStencilStateToHandle(state);
}

void mtl4SetBlendState(GpuCommandBuffer cb, GpuBlendState state, GpuResult* result) {
	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}
	
	metadata->blend = mtl4GpuBlendStateToHandle(state);
}

void mtl4SignalAfter(GpuCommandBuffer cb, GpuStageFlags before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result) {
	(void)signal;
	(void)before;

	CmnResult localResult;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4Command command = {};
	command.type = MTL4_CMD_SIGNAL;
	command.barrier.stages = before;
	command.signal.signal = ptrGpu;
	command.signal.value = value;

	mtl4FlushBarriers(metadata);

	cmnAppend(&metadata->commands, command, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4WaitBefore(GpuCommandBuffer cb, GpuStageFlags after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result) {
	(void)after;
	(void)op;
	(void)hazards;
	(void)mask;

	CmnResult localResult;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4Command command = {};
	command.type = MTL4_CMD_WAIT;
	command.wait.signal = ptrGpu;
	command.wait.value = value;

	mtl4FlushBarriers(metadata);

	cmnAppend(&metadata->commands, command, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4Dispatch(GpuCommandBuffer cb, void* dataGpu, uint32_t gridDimensions[3], GpuResult* result) {

	CmnResult localResult;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4Command command = {};
	command.type = MTL4_CMD_DISPATCH;
	command.dispatch.data = dataGpu;
	command.dispatch.pipeline = metadata->pipeline;
	memcpy(command.dispatch.gridDimensions, gridDimensions, sizeof(uint32_t) * 3);

	mtl4GetBarrierFor(metadata, GPU_STAGE_COMPUTE, &command.barrier.stages, &command.barrier.stages);

	cmnAppend(&metadata->commands, command, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4DispatchIndirect(GpuCommandBuffer cb, void* dataGpu, void* gridDimensionsGpu, GpuResult* result) {

	CmnResult localResult;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4Command command = {};
	command.type = MTL4_CMD_DISPATCH_INDIRECT;
	command.dispatchIndirect.data = dataGpu;
	command.dispatchIndirect.indirectArgs = gridDimensionsGpu;
	command.dispatchIndirect.pipeline = metadata->pipeline;

	mtl4GetBarrierFor(metadata, GPU_STAGE_COMPUTE, &command.barrier.stages, &command.barrier.stages);

	cmnAppend(&metadata->commands, command, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4BeginRenderPass(GpuCommandBuffer cb, const GpuRenderPassDesc* desc, GpuResult* result) {
	
	GpuResult localResult;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	metadata->activeRenderPass = {};
	metadata->activeRenderPass.type = MTL4_CMD_RENDERPASS;
	metadata->activeRenderPass.renderPass.desc = mtl4CopyRenderPassDesc(metadata, desc, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}

	 mtl4GetBarrierFor(
		metadata,
		GPU_STAGE_VERTEX_SHADER,
		&metadata->activeRenderPass.renderBarrier.vertex.stages,
		&metadata->activeRenderPass.renderBarrier.vertex.hazards);
	 mtl4GetBarrierFor(
		metadata,
		GPU_STAGE_PIXEL_SHADER,
		&metadata->activeRenderPass.renderBarrier.fragment.stages,
		&metadata->activeRenderPass.renderBarrier.fragment.hazards);

	metadata->isEncodingRenderpass = true;
}

void mtl4EndRenderPass(GpuCommandBuffer cb, GpuResult* result) {
	CmnResult localResult;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	cmnAppend(&metadata->commands, metadata->activeRenderPass, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
	} else {
		CMN_SET_RESULT(result, GPU_SUCCESS);
	}

	metadata->activeRenderPass = {};
	metadata->isEncodingRenderpass = false;
}

void mtl4DrawIndexedInstanced(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, uint32_t indexCount, uint32_t instanceCount, GpuResult* result) {
	CmnResult localResult;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4RenderCommand command = {};
	command.type = MTL4_CMD_DRAW;
	command.pipeline = metadata->pipeline;
	command.textureHeapPtr = metadata->textureHeapPtr;
	command.blend = metadata->blend;
	command.depthStencil = metadata->depthStencil;
	command.draw.vertexData = vertexDataGpu;
	command.draw.pixelData = pixelDataGpu;
	command.draw.indices = indicesGpu;
	command.draw.indexCount = indexCount;
	command.draw.instanceCount = instanceCount;

	cmnInsert(&metadata->activeRenderPass.renderPass.commands, command, metadata->allocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4DrawIndexedInstancedIndirect(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, void* argsGpu, GpuResult* result) {
	CmnResult localResult;
	
	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4RenderCommand command = {};
	command.type = MTL4_CMD_DRAW_INDIRECT;
	command.pipeline = metadata->pipeline;
	command.textureHeapPtr = metadata->textureHeapPtr;
	command.blend = metadata->blend;
	command.depthStencil = metadata->depthStencil;
	command.drawIndirect.vertexData = vertexDataGpu;
	command.drawIndirect.pixelData = pixelDataGpu;
	command.drawIndirect.indices = indicesGpu;
	command.drawIndirect.indirectArgs = argsGpu;

	cmnInsert(&metadata->activeRenderPass.renderPass.commands, command, metadata->allocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	metadata->activeRenderPass.renderPass.requiresPreparation = true;
	metadata->activeRenderPass.renderPass.containsIndirectDraw = true;

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4DrawIndexedInstancedIndirectMulti(GpuCommandBuffer cb, void* dataVxGpu, uint32_t vxStride, void* dataPxGpu, uint32_t pxStride, void* argsGpu, void* drawCountGpu, GpuResult* result) {
	CmnResult localResult;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4RenderCommand command = {};
	command.type = MTL4_CMD_MULTIDRAW_INDIRECT;
	command.pipeline = metadata->pipeline;
	command.textureHeapPtr = metadata->textureHeapPtr;
	command.blend = metadata->blend;
	command.depthStencil = metadata->depthStencil;
	command.multiDrawIndirect.vertexData = dataVxGpu;
	command.multiDrawIndirect.vertexStride = vxStride;
	command.multiDrawIndirect.pixelData = dataPxGpu;
	command.multiDrawIndirect.pixelStride = pxStride;
	command.multiDrawIndirect.indirectArgs = argsGpu;
	command.multiDrawIndirect.indirectDrawCount = drawCountGpu;

	cmnInsert(&metadata->activeRenderPass.renderPass.commands, command, metadata->allocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	metadata->activeRenderPass.renderPass.requiresPreparation = true;
	metadata->activeRenderPass.renderPass.containsMultiDraw = true;
	
	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4GetBarrierFor(Mtl4CommandBufferMetadata* metadata, GpuStage after, GpuStageFlags* before, GpuHazardFlags* hazards) {
	size_t index = __builtin_ctzll(after);

	*before = metadata->barriersForQueueState[index].before;
	*hazards = metadata->barriersForQueueState[index].hazards;

	metadata->barriersForQueueState[index] = {};
}
void mtl4AddBarrierFor(Mtl4CommandBufferMetadata* metadata, GpuStage after, GpuStageFlags before, GpuHazardFlags hazards) {
	size_t index = __builtin_ctzll(after);

	metadata->barriersForQueueState[index].before |= before;
	metadata->barriersForQueueState[index].hazards |= hazards;
}

void mtl4FlushBarriers(Mtl4CommandBufferMetadata* metadata) {
	for (size_t i = 0; i < MTL4_GPU_STAGES_COUNT; i++) {
		metadata->barriersForQueueState[i] = {};
	}
}

GpuRenderPassDesc* mtl4CopyRenderPassDesc(Mtl4CommandBufferMetadata* metadata, const GpuRenderPassDesc* desc, GpuResult* result) {
	CmnResult localResult;

	GpuRenderPassDesc* descCopy = cmnAlloc<GpuRenderPassDesc>(metadata->allocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return nullptr;
	}
	memcpy(descCopy, desc, sizeof(GpuRenderPassDesc));

	if (desc->depthTarget != nullptr) {
		descCopy->depthTarget = cmnAlloc<GpuRenderTarget>(metadata->allocator, &localResult);
		if (localResult != CMN_SUCCESS) {
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return nullptr;
		}
		memcpy(descCopy->depthTarget, desc->depthTarget, sizeof(GpuRenderTarget));
	}

	if (desc->stencilTarget != nullptr) {
		descCopy->stencilTarget = cmnAlloc<GpuRenderTarget>(metadata->allocator, &localResult);
		if (localResult != CMN_SUCCESS) {
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return nullptr;
		}
		memcpy(descCopy->stencilTarget, desc->stencilTarget, sizeof(GpuRenderTarget));
	}

	if (desc->colorTargets != nullptr) {
		descCopy->colorTargets = cmnAlloc<GpuRenderTarget>(metadata->allocator, desc->colorTargetCount, &localResult);
		if (localResult != CMN_SUCCESS) {
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return nullptr;
		}
		memcpy(descCopy->colorTargets, desc->colorTargets, sizeof(GpuRenderTarget) * desc->colorTargetCount);
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return descCopy;
}

Mtl4CommandBufferMetadata* mtl4AcquireCommandBufferMetadataFrom(Mtl4CommandBuffer handle) {
	CmnScopedReadRWMutex guard(&gMtl4CommandBufferStorage.commandBuffersMutex);

	bool wasHandleValid;
	Mtl4CommandBufferMetadata* metadata = &cmnGet(&gMtl4CommandBufferStorage.commandBuffers, handle, &wasHandleValid);
	if (!wasHandleValid) {
		return nullptr;
	}

	return metadata;
}

