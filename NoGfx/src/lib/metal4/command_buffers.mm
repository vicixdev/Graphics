#include "command_buffers.h"
#include "lib/metal4/encoding_context.h"

#include <lib/common/heap_allocator.h>
#include <lib/common/atomic.h>
#include <lib/common/futex.h>
#include <lib/metal4/context.h>
#include <lib/metal4/tables.h>
#include <lib/metal4/allocation.h>
#include <lib/metal4/events.h>
#include <lib/metal4/semaphores.h>

Mtl4CommandBufferStorage gMtl4CommandBufferStorage;

void mtl4InitCommandBufferStorage(GpuResult* result) {

	CmnResult localResult;

	gMtl4CommandBufferStorage = {};

	cmnCreateStaticHandleMap(&gMtl4CommandBufferStorage.commandBuffers, {});

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		gMtl4CommandBufferStorage.emissionContexts[i].bumpBuffer = [gMtl4Context.device
			newBufferWithLength:1024*1024
			options:MTLResourceStorageModeShared | MTLResourceCPUCacheModeWriteCombined
		];
		mtl4AddAllocationToResidencySet(gMtl4CommandBufferStorage.emissionContexts[i].bumpBuffer);
	}

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		gMtl4CommandBufferStorage.pages[i] = cmnCreatePage(1024 * 1024 * 32, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
		if (localResult != CMN_SUCCESS) {
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return;
		}

		gMtl4CommandBufferStorage.arenas[i] = cmnPageToArena(gMtl4CommandBufferStorage.pages[i]);
	}

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		id<MTL4CommandAllocator> commandAllocator = [gMtl4Context.device newCommandAllocator];
		if (commandAllocator == nil) {
			CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
			return;
		}

		gMtl4CommandBufferStorage.emissionContexts[i].commandAllocator = commandAllocator;
	}

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		id<MTL4CommandQueue> queue = [gMtl4Context.device newMTL4CommandQueue];
		if (queue == nil) {
			CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
			return;
		}

		gMtl4CommandBufferStorage.emissionContexts[i].queue = queue;
		[queue addResidencySet:gMtl4AllocationStorage.residencySet];
		[queue addResidencySet:gMtl4EventStorage.uploadBufferResidencySet];
	}

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		id<MTLSharedEvent> event = [gMtl4Context.device newSharedEvent];
		if (event == nil) {
			CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
			return;
		}

		gMtl4CommandBufferStorage.emissionContexts[i].submitEvent = event;
	}

	MTL4ArgumentTableDescriptor* computeArgumentTableDesc = [[MTL4ArgumentTableDescriptor new] autorelease];
	computeArgumentTableDesc.maxBufferBindCount = 1;
	computeArgumentTableDesc.maxSamplerStateBindCount = 0;
	computeArgumentTableDesc.maxTextureBindCount = 0;

	MTL4ArgumentTableDescriptor* vertexArgumentTableDesc = [[MTL4ArgumentTableDescriptor new] autorelease];
	vertexArgumentTableDesc.maxBufferBindCount = 1;
	vertexArgumentTableDesc.maxSamplerStateBindCount = 0;
	vertexArgumentTableDesc.maxTextureBindCount = 0;

	MTL4ArgumentTableDescriptor* fragmentArgumentTableDesc = [[MTL4ArgumentTableDescriptor new] autorelease];
	fragmentArgumentTableDesc.maxBufferBindCount = 2;
	fragmentArgumentTableDesc.maxSamplerStateBindCount = 0;
	fragmentArgumentTableDesc.maxTextureBindCount = 0;

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		id<MTL4ArgumentTable> argumentTable = [gMtl4Context.device
			newArgumentTableWithDescriptor:computeArgumentTableDesc
			error:nullptr];
		if (argumentTable == nil) {
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return;
		}

		gMtl4CommandBufferStorage.emissionContexts[i].computeArgumentTable = argumentTable;
	}

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		id<MTL4ArgumentTable> argumentTable = [gMtl4Context.device
			newArgumentTableWithDescriptor:vertexArgumentTableDesc
			error:nullptr];
		if (argumentTable == nil) {
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return;
		}

		gMtl4CommandBufferStorage.emissionContexts[i].vertexArgumentTable = argumentTable;
	}


	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		id<MTL4ArgumentTable> argumentTable = [gMtl4Context.device
			newArgumentTableWithDescriptor:fragmentArgumentTableDesc
			error:nullptr];
		if (argumentTable == nil) {
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return;
		}

		gMtl4CommandBufferStorage.emissionContexts[i].fragmentArgumentTable = argumentTable;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4FiniCommandBufferStorage(void) {
	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		if (gMtl4CommandBufferStorage.emissionContexts[i].commandAllocator != nil) {
			[gMtl4CommandBufferStorage.emissionContexts[i].commandAllocator release];
		}
	}

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		if (gMtl4CommandBufferStorage.emissionContexts[i].queue != nil) {
			[gMtl4CommandBufferStorage.emissionContexts[i].queue release];
		}
	}

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		if (gMtl4CommandBufferStorage.emissionContexts[i].computeArgumentTable != nil) {
			[gMtl4CommandBufferStorage.emissionContexts[i].computeArgumentTable release];
		}
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

	if (lastCommandBufferError == GPU_SUCCESS && didFindAllCommandBuffers) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
	} else if (lastCommandBufferError != GPU_SUCCESS) {
		CMN_SET_RESULT(result, lastCommandBufferError);
	} else {
		CMN_SET_RESULT(result, GPU_SUCCESS);
	}
}

void mtl4Submit(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result) {
	(void)queue;

	Mtl4CommandEmissionContext* emitContext = mtl4AcquireEmissionContext();
	defer (mtl4ReleaseEmissionContext(emitContext));

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

	Mtl4CommandEmissionContext* emitContext = mtl4AcquireEmissionContext();
	defer (mtl4ReleaseEmissionContext(emitContext));

	mtl4Submit(emitContext, commandBuffers, commandBufferCount, result);
	mtl4EmitSignal(emitContext, mtl4GpuSemaphoreToHandle(semaphore), value, result);
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

	mtl4GetBarrierFor(metadata, GPU_STAGE_TRANSFER, &command.waitFor, &command.waitingHazards);

	cmnAppend(&metadata->commands, command, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4CopyToTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result) {}
void mtl4CopyFromTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result) {}

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

	// TODO: Move to validation
	// Mtl4Pipeline pipelineHandle = mtl4GpuPipelineToHandle(pipeline);
	// Mtl4PipelineMetadata* pipelineMetadata = mtl4AcquirePipelineMetadataFrom(pipelineHandle);
	// if (pipelineMetadata == nullptr) {
	// 	CMN_SET_RESULT(result, GPU_NO_SUCH_PIPELINE_FOUND);
	// 	return;
	// }
	// defer (mtl4ReleasePipelineMetadata());

	// if (pipelineMetadata->type != MTL4_PIPELINE_COMPUTE) {
	// 	CMN_SET_RESULT(result, GPU_INCOMPATIBLE_PIPELINE);
	// 	return;
	// }

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
	command.waitFor = before;
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

	mtl4GetBarrierFor(metadata, GPU_STAGE_COMPUTE, &command.waitFor, &command.waitingHazards);

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

	mtl4GetBarrierFor(metadata, GPU_STAGE_COMPUTE, &command.waitFor, &command.waitingHazards);

	cmnAppend(&metadata->commands, command, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4BeginRenderPass(GpuCommandBuffer cb, const GpuRenderPassDesc* desc, GpuResult* result) {}
void mtl4EndRenderPass(GpuCommandBuffer cb, GpuResult* result) {}

void mtl4DrawIndexedInstanced(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, uint32_t indexCount, uint32_t instanceCount, GpuResult* result) {}
void mtl4DrawIndexedInstancedIndirect(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, void* argsGpu, GpuResult* result) {}

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

GpuResult* mtl4CopyRenderPassDesc(Mtl4CommandBufferMetadata* metadata, const GpuRenderPassDesc* desc, GpuResult* result) {}

Mtl4CommandEmissionContext* mtl4AcquireEmissionContext(void) {
	size_t index;
	for (;;) {
		index = cmnAtomicAdd(&gMtl4CommandBufferStorage.emissionContextIdx, (size_t)1);

		if (!cmnAtomicExchange(&gMtl4CommandBufferStorage.emissionContexts[index].inUse, true)) {
			break;
		}
	}

	[gMtl4AllocationStorage.residencySet commit];
	return &gMtl4CommandBufferStorage.emissionContexts[index];
}

void mtl4ReleaseEmissionContext(Mtl4CommandEmissionContext* context) {
	cmnAtomicStore(&context->inUse, false);
}

// GpuCommandBuffer mtl4StartCommandEncoding(GpuQueue queue, GpuResult* result) {
// 	(void)queue;

// 	Mtl4CommandBuffer handle;
// 	id<MTL4CommandQueue> mtlQueue;
// 	id<MTL4CommandAllocator> mtlAllocator;
// 	id<MTLSharedEvent> submitEvent;
// 	id<MTL4ArgumentTable> computeArgumentTable;
// 	id<MTL4ArgumentTable> vertexArgumentTable;
// 	id<MTL4ArgumentTable> fragmentArgumentTable;
// 	size_t indirectDrawArgsOffset;

// 	if (!mtl4AcquireResourcesForNewCommandBuffer(
// 		&handle,
// 		&mtlQueue,
// 		&mtlAllocator,
// 		&computeArgumentTable,
// 		&vertexArgumentTable,
// 		&fragmentArgumentTable,
// 		&submitEvent,
// 		&indirectDrawArgsOffset
// 	)) {
// 		CMN_SET_RESULT(result, GPU_TOO_MANY_UNSUBMITTED_COMMAND_BUFFERS);
// 		return {};
// 	}

// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	assert(metadata != nullptr);

// 	metadata->status = MTL4_COMMAND_BUFFER_ENCODING;
// 	metadata->queue = mtlQueue;
// 	metadata->submitEvent = submitEvent;
// 	metadata->commandAllocator = mtlAllocator;
// 	metadata->computeArgumentTable = computeArgumentTable;
// 	metadata->vertexArgumentTable = vertexArgumentTable;
// 	metadata->fragmentArgumentTable = fragmentArgumentTable;
// 	metadata->indirectDrawArgsBufferOffset = indirectDrawArgsOffset;

// 	uint64_t submitCount = cmnAtomicLoad(&gMtl4CommandBufferStorage.submitCount);
// 	[metadata->queue waitForEvent:submitEvent value:submitCount];

// 	[gMtl4AllocationStorage.residencySet commit];

// 	CMN_SET_RESULT(result, GPU_SUCCESS);
// 	return mtl4HandleToGpuCommandBuffer(handle);
// }

// void mtl4Submit(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result) {
// 	for (size_t i = 0; i < commandBufferCount; i++) {
// 		mtl4SubmitSingleBuffer(queue, commandBuffers[i], nullptr, 0, result);
// 	}
// }

// void mtl4SubmitWithSignal(
// 	GpuQueue queue,
// 	GpuCommandBuffer* commandBuffers,
// 	size_t commandBufferCount,
// 	GpuSemaphore semaphore,
// 	uint64_t value,
// 	GpuResult* result
// ) {
// 	Mtl4Semaphore semaphoreHandle = mtl4GpuSemaphoreToHandle(semaphore);
// 	Mtl4SemaphoreMetadata* semaphoreMetadata = mtl4AcquireSemaphoreMetadataFrom(semaphoreHandle);
// 	if (semaphoreMetadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_SEMAPHORE_FOUND);
// 		return;
// 	}

// 	for (size_t i = 0; i < commandBufferCount; i++) {
// 		mtl4SubmitSingleBuffer(queue, commandBuffers[i], semaphoreMetadata->events[i], value, result);
// 	}
// 	semaphoreMetadata->lastSignalCount = commandBufferCount;
// }
// void mtl4MemCpy(GpuCommandBuffer cb, void* destGpu, void* srcGpu, size_t size, GpuResult* result) {

// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}

// 	Mtl4AllocationMetadata* destinationMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(destGpu, true);
// 	if (destinationMetadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
// 		return;
// 	}
// 	defer (mtl4ReleaseAllocationMetadata());

// 	Mtl4AllocationMetadata* sourceMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(srcGpu, true);
// 	if (sourceMetadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
// 		return;
// 	}
// 	defer (mtl4ReleaseAllocationMetadata());

// 	size_t destinationOffset = mtl4GpuPtrOffsetFromBase(destinationMetadata, destGpu);
// 	size_t sourceOffset = mtl4GpuPtrOffsetFromBase(sourceMetadata, srcGpu);

// 	mtl4EnsureValidComputeEndoderFor(metadata);
// 	[metadata->computeEncoder
// 	 	copyFromBuffer:sourceMetadata->buffer sourceOffset:sourceOffset
// 		toBuffer:destinationMetadata->buffer destinationOffset:destinationOffset
// 		size:size];

// 	CMN_SET_RESULT(result, GPU_SUCCESS);
// }

// void mtl4CopyToTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result) {
// 	(void)destGpu;
	
// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}

// 	Mtl4AllocationMetadata* sourceMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(srcGpu, true);
// 	if (sourceMetadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
// 		return;
// 	}
// 	defer (mtl4ReleaseAllocationMetadata());

// 	Mtl4Texture textureHandle = mtl4GpuTextureToHadle(texture);
// 	Mtl4TextureMetadata* textureMetadata = mtl4AcquireTextureMetadataFrom(textureHandle);
// 	if (textureMetadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_TEXTURE_FOUND);
// 		return;
// 	}
// 	defer (mtl4ReleaseTextureMetadata());

// 	// TODO: Support arrays.
// 	if (textureMetadata->descriptor.type == GPU_TEXTURE_2D_ARRAY ||
// 		textureMetadata->descriptor.type == GPU_TEXTURE_CUBE_ARRAY
// 	) {
// 		assert(false && "Unimplemented");
// 	}

// 	MTLSize textureSize = MTLSizeMake(
// 		textureMetadata->descriptor.dimensions[0],
// 		textureMetadata->descriptor.dimensions[1],
// 		textureMetadata->descriptor.dimensions[2]
// 	);
// 	size_t bytesPerRow = textureMetadata->descriptor.dimensions[0] * gMtl4GpuFormatPixelSize[textureMetadata->descriptor.format];
// 	size_t bytesPerImage = textureMetadata->descriptor.dimensions[0] *
// 				textureMetadata->descriptor.dimensions[1] *
// 				textureMetadata->descriptor.dimensions[2] *
// 				gMtl4GpuFormatPixelSize[textureMetadata->descriptor.format];

// 	size_t sourceOffset = mtl4GpuPtrOffsetFromBase(sourceMetadata, srcGpu);

// 	// TODO: Support mipmaps.
// 	mtl4EnsureValidComputeEndoderFor(metadata);
// 	[metadata->computeEncoder copyFromBuffer:sourceMetadata->buffer
// 	 	sourceOffset:sourceOffset
// 		sourceBytesPerRow:bytesPerRow
// 		sourceBytesPerImage:bytesPerImage
// 		sourceSize:textureSize
// 		toTexture:textureMetadata->texture
// 		destinationSlice:0
// 		destinationLevel:0
// 		destinationOrigin:MTLOriginMake(0, 0, 0)];

// 	CMN_SET_RESULT(result, GPU_SUCCESS);
// }

// void mtl4CopyFromTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result) {
// 	(void)srcGpu;

// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}

// 	Mtl4AllocationMetadata* destinationMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(destGpu, true);
// 	if (destinationMetadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
// 		return;
// 	}
// 	defer (mtl4ReleaseAllocationMetadata());

// 	Mtl4Texture textureHandle = mtl4GpuTextureToHadle(texture);
// 	Mtl4TextureMetadata* textureMetadata = mtl4AcquireTextureMetadataFrom(textureHandle);
// 	if (textureMetadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_TEXTURE_FOUND);
// 		return;
// 	}
// 	defer (mtl4ReleaseTextureMetadata());

// 	// TODO: Support arrays.
// 	if (textureMetadata->descriptor.type == GPU_TEXTURE_2D_ARRAY ||
// 		textureMetadata->descriptor.type == GPU_TEXTURE_CUBE_ARRAY
// 	) {
// 		assert(false && "Unimplemented");
// 	}

// 	MTLSize textureSize = MTLSizeMake(
// 		textureMetadata->descriptor.dimensions[0],
// 		textureMetadata->descriptor.dimensions[1],
// 		textureMetadata->descriptor.dimensions[2]
// 	);
// 	size_t bytesPerRow = textureMetadata->descriptor.dimensions[0] * gMtl4GpuFormatPixelSize[textureMetadata->descriptor.format];
// 	size_t bytesPerImage = textureMetadata->descriptor.dimensions[0] *
// 				textureMetadata->descriptor.dimensions[1] *
// 				textureMetadata->descriptor.dimensions[2] *
// 				gMtl4GpuFormatPixelSize[textureMetadata->descriptor.format];

// 	size_t destinationOffset = mtl4GpuPtrOffsetFromBase(destinationMetadata, destGpu);

// 	// TODO: Support mipmaps.
// 	mtl4EnsureValidComputeEndoderFor(metadata);
// 	[metadata->computeEncoder copyFromTexture:textureMetadata->texture
// 		sourceSlice:0
// 		sourceLevel:0
// 		sourceOrigin:MTLOriginMake(0, 0, 0)
// 		sourceSize:textureSize
// 		toBuffer:destinationMetadata->buffer
// 		destinationOffset:destinationOffset
// 		destinationBytesPerRow:bytesPerRow
// 		destinationBytesPerImage:bytesPerImage
// 	];

// }


// void mtl4Barrier(GpuCommandBuffer cb, GpuStageFlags before, GpuStageFlags after, GpuHazardFlags hazards, GpuResult* result) {
// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}

// 	MTLStages metalBefore = mtl4GpuToMtlStage(before);
// 	MTLStages metalAfter = mtl4GpuToMtlStage(after);
// 	MTL4VisibilityOptions metalVisibilityOptions = mtl4GpuHazardsToMtlVisibilityOptions(hazards);

// 	// TODO: Validate that there is not an active render pass...

// 	if (mtl4IsStageCompute(before)) {
// 		mtl4FlushCommandEncoderOf(metadata);
// 	}

// 	if (mtl4IsStageCompute(after)) {
// 		mtl4EnsureValidComputeEndoderFor(metadata);
// 		[metadata->computeEncoder
// 			barrierAfterQueueStages:metalBefore
// 			beforeStages:metalAfter & (MTLStageBlit | MTLStageDispatch)
// 			visibilityOptions:metalVisibilityOptions];
// 	}

// 	for (size_t i = 0; i < MTL4_GPU_STAGES_COUNT; i++) {
// 		GpuStage stage = (GpuStage)(1 << i);

// 		if (!(before & stage)) {
// 			continue;
// 		}

// 		metadata->renderBarrierForQueueState[i].after |= after & (GPU_STAGE_PIXEL_SHADER | GPU_STAGE_RASTER_COLOR_OUT | GPU_STAGE_VERTEX_SHADER);
// 		metadata->renderBarrierForQueueState[i].hazards |= hazards;
// 	}

// 	CMN_SET_RESULT(result, GPU_SUCCESS);
// }

// void mtl4SignalAfter(GpuCommandBuffer cb, GpuStageFlags before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result) {
// 	assert(signal == GPU_SIGNAL_ATOMIC_MAX && "The only supported signal operation is GPU_SIGNAL_ATOMIC_MAX.");

// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}

// 	mtl4SignalEvent(metadata, before, ptrGpu, value, result);
// }

// void mtl4WaitBefore(GpuCommandBuffer cb, GpuStageFlags after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result) {
// 	(void)hazards;
// 	assert(op == GPU_OP_GREATER_EQUAL && "The only supported wait operation is GPU_OP_GREATER_EQUAL.");
// 	assert(mask == ~(uint64_t)0 && "The only supported mask is ~0.");

// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}

// 	mtl4WaitEvent(metadata, after, ptrGpu, value, result);
// }

// void mtl4Dispatch(GpuCommandBuffer cb, void* dataGpu, uint32_t gridDimensions[3], GpuResult* result) {

// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}

// 	Mtl4PipelineMetadata* pipelineMetadata = mtl4AcquirePipelineMetadataFrom(metadata->pipeline);
// 	if (pipelineMetadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_PIPELINE_FOUND);
// 		return;
// 	}

// 	if (pipelineMetadata->type != MTL4_PIPELINE_COMPUTE) {
// 		CMN_SET_RESULT(result, GPU_INCOMPATIBLE_PIPELINE);
// 		return;
// 	}
// 	defer (mtl4ReleasePipelineMetadata());

// 	Mtl4AllocationMetadata* allocationMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(dataGpu, true);
// 	if (allocationMetadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
// 		return;
// 	}
// 	defer (mtl4ReleaseAllocationMetadata());

// 	size_t gpuPointerOffset = mtl4GpuPtrOffsetFromBase(allocationMetadata, dataGpu);

// 	MTLGPUAddress baseGpuAddress = [allocationMetadata->buffer gpuAddress] + gpuPointerOffset;
// 	[metadata->computeArgumentTable setAddress:baseGpuAddress atIndex:0];

// 	mtl4EnsureValidComputeEndoderFor(metadata);
// 	[metadata->computeEncoder setComputePipelineState:pipelineMetadata->compute.pso];
// 	[metadata->computeEncoder setArgumentTable:metadata->computeArgumentTable];
// 	[metadata->computeEncoder
// 		dispatchThreadgroups:MTLSizeMake(gridDimensions[0], gridDimensions[1], gridDimensions[2])
// 		threadsPerThreadgroup:MTLSizeMake(pipelineMetadata->compute.groupSize[0], pipelineMetadata->compute.groupSize[1], pipelineMetadata->compute.groupSize[2])];

// 	CMN_SET_RESULT(result, GPU_SUCCESS);
// 	return;
// }

// void mtl4DispatchIndirect(GpuCommandBuffer cb, void* dataGpu, void* gridDimensionsGpu, GpuResult* result) {
// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}

// 	Mtl4PipelineMetadata* pipelineMetadata = mtl4AcquirePipelineMetadataFrom(metadata->pipeline);
// 	if (pipelineMetadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_PIPELINE_FOUND);
// 		return;
// 	}

// 	if (pipelineMetadata->type != MTL4_PIPELINE_COMPUTE) {
// 		CMN_SET_RESULT(result, GPU_INCOMPATIBLE_PIPELINE);
// 		return;
// 	}
// 	defer (mtl4ReleasePipelineMetadata());

// 	Mtl4AllocationMetadata* allocationMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(dataGpu, true);
// 	if (allocationMetadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
// 		return;
// 	}
// 	defer (mtl4ReleaseAllocationMetadata());

// 	size_t gpuPointerOffset = mtl4GpuPtrOffsetFromBase(allocationMetadata, dataGpu);

// 	MTLGPUAddress baseGpuAddress = [allocationMetadata->buffer gpuAddress] + gpuPointerOffset;
// 	[metadata->computeArgumentTable setAddress:baseGpuAddress atIndex:0];

// 	// TODO: In the validation, check that gridDimensionsGpu is 4-word aligned

// 	mtl4EnsureValidComputeEndoderFor(metadata);
// 	[metadata->computeEncoder setComputePipelineState:pipelineMetadata->compute.pso];
// 	[metadata->computeEncoder setArgumentTable:metadata->computeArgumentTable];
// 	[metadata->computeEncoder
// 		dispatchThreadgroupsWithIndirectBuffer:(uintptr_t)gridDimensionsGpu
// 		threadsPerThreadgroup:MTLSizeMake(pipelineMetadata->compute.groupSize[0], pipelineMetadata->compute.groupSize[1], pipelineMetadata->compute.groupSize[2])];

// 	CMN_SET_RESULT(result, GPU_SUCCESS);
// 	return;
// }

// void mtl4BeginRenderPass(GpuCommandBuffer cb, const GpuRenderPassDesc* desc, GpuResult* result) {
// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}

// 	MTL4RenderPassDescriptor* renderPassDesc = [[MTL4RenderPassDescriptor new] autorelease];

// 	for (size_t i = 0; i < desc->colorTargetCount; i++) {
// 		const GpuRenderTarget* target = &desc->colorTargets[i];

// 		Mtl4Texture targetTextureHandle = mtl4GpuTextureToHadle(target->texture);
// 		Mtl4TextureMetadata* targetTexture = mtl4AcquireTextureMetadataFrom(targetTextureHandle);
// 		if (targetTexture == nullptr) {
// 			CMN_SET_RESULT(result, GPU_NO_SUCH_TEXTURE_FOUND);
// 			return;
// 		}
// 		defer (mtl4ReleaseTextureMetadata());

// 		MTLRenderPassColorAttachmentDescriptor* colorAttachment = [[MTLRenderPassColorAttachmentDescriptor new] autorelease];
// 		colorAttachment.texture = targetTexture->texture;
// 		colorAttachment.loadAction = gMtl4GpuTargetOpToMtlLoadAction[target->loadOp];
// 		colorAttachment.storeAction = gMtl4GpuTargetOpToMtlStoreAction[target->storeOp];
// 		colorAttachment.clearColor = MTLClearColorMake(
// 			target->clearColor[0],
// 			target->clearColor[1],
// 			target->clearColor[2],
// 			target->clearColor[3]
// 		);

// 		renderPassDesc.colorAttachments[i] = colorAttachment;

// 	}

// 	if (desc->depthTarget != nullptr) {
// 		Mtl4Texture depthTargetHandle = mtl4GpuTextureToHadle(desc->depthTarget->texture);
// 		Mtl4TextureMetadata* depthTarget = mtl4AcquireTextureMetadataFrom(depthTargetHandle);
// 		if (depthTarget == nullptr) {
// 			CMN_SET_RESULT(result, GPU_NO_SUCH_TEXTURE_FOUND);
// 			return;
// 		}
// 		defer (mtl4ReleaseTextureMetadata());

// 		MTLRenderPassDepthAttachmentDescriptor* depthAttachment = [[MTLRenderPassDepthAttachmentDescriptor new] autorelease];
// 		depthAttachment.texture = depthTarget->texture;
// 		depthAttachment.clearDepth = desc->depthTarget->depthClearValue;
// 		depthAttachment.loadAction = gMtl4GpuTargetOpToMtlLoadAction[desc->depthTarget->loadOp];
// 		depthAttachment.storeAction = gMtl4GpuTargetOpToMtlStoreAction[desc->depthTarget->storeOp];

// 		renderPassDesc.depthAttachment = depthAttachment;
// 	}

// 	if (desc->stencilTarget != nullptr) {
// 		Mtl4Texture stencilTargetHandle = mtl4GpuTextureToHadle(desc->stencilTarget->texture);
// 		Mtl4TextureMetadata* stencilTarget = mtl4AcquireTextureMetadataFrom(stencilTargetHandle);
// 		if (stencilTarget == nullptr) {
// 			CMN_SET_RESULT(result, GPU_NO_SUCH_TEXTURE_FOUND);
// 			return;
// 		}
// 		defer (mtl4ReleaseTextureMetadata());

// 		MTLRenderPassStencilAttachmentDescriptor* stencilAttachment = [[MTLRenderPassStencilAttachmentDescriptor new] autorelease];
// 		stencilAttachment.texture = stencilTarget->texture;
// 		stencilAttachment.clearStencil = desc->stencilTarget->stencilClearValue;
// 		stencilAttachment.loadAction = gMtl4GpuTargetOpToMtlLoadAction[desc->stencilTarget->loadOp];
// 		stencilAttachment.storeAction = gMtl4GpuTargetOpToMtlStoreAction[desc->stencilTarget->storeOp];

// 		renderPassDesc.stencilAttachment = stencilAttachment;
// 	}

// 	mtl4EnsureValidCommandBuffer(metadata);
// 	metadata->renderEncoder = [metadata->commandBuffer renderCommandEncoderWithDescriptor:renderPassDesc];

// 	for (size_t i = 0; i < MTL4_GPU_STAGES_COUNT; i++) {
// 		GpuStage stage = (GpuStage)(1 << i);

// 		if (metadata->renderBarrierForQueueState[i].after == 0) {
// 			continue;
// 		}

// 		MTLStages before = mtl4GpuToMtlStage(stage);
// 		MTLStages after = mtl4GpuToMtlStage(metadata->renderBarrierForQueueState[i].after);
// 		MTL4VisibilityOptions visibility = mtl4GpuHazardsToMtlVisibilityOptions(metadata->renderBarrierForQueueState[i].hazards);

// 		[metadata->renderEncoder
// 			barrierAfterQueueStages:before
// 			beforeStages:after
// 			visibilityOptions:visibility];
// 	}
// }

// void mtl4EndRenderPass(GpuCommandBuffer cb, GpuResult* result) {
// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}

// 	[metadata->renderEncoder endEncoding];
// }

// void mtl4DrawIndexedInstanced(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, uint32_t indexCount, uint32_t instanceCount, GpuResult* result) {
// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}

// 	Mtl4PipelineMetadata* pipeline = mtl4AcquirePipelineMetadataFrom(metadata->pipeline);
// 	if (pipeline == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_PIPELINE_FOUND);
// 		return;
// 	}
// 	defer (mtl4ReleasePipelineMetadata());

// 	[metadata->vertexArgumentTable setAddress:(uintptr_t)vertexDataGpu atIndex:0];

// 	[metadata->fragmentArgumentTable setAddress:(uintptr_t)pixelDataGpu atIndex:0];
// 	[metadata->fragmentArgumentTable setAddress:(uintptr_t)metadata->textureHeapPtr atIndex:1];

// 	[metadata->renderEncoder setArgumentTable:metadata->vertexArgumentTable atStages:MTLStageVertex];
// 	[metadata->renderEncoder setArgumentTable:metadata->fragmentArgumentTable atStages:MTLStageFragment];
// 	[metadata->renderEncoder setRenderPipelineState:pipeline->graphics.pso];
// 	[metadata->renderEncoder
// 		drawIndexedPrimitives:gMtl4GpuTopologyToMtlPrimitive[pipeline->graphics.desc.topology]
// 		indexCount:indexCount
// 		indexType:MTLIndexTypeUInt32
// 		indexBuffer:(uintptr_t)indicesGpu
// 		indexBufferLength:sizeof(uint32_t) * indexCount
// 		instanceCount:instanceCount];
// }

// void mtl4DrawIndexedInstancedIndirect(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, void* argsGpu, GpuResult* result) {
// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}

// 	Mtl4PipelineMetadata* pipeline = mtl4AcquirePipelineMetadataFrom(metadata->pipeline);
// 	if (pipeline == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_PIPELINE_FOUND);
// 		return;
// 	}
// 	defer (mtl4ReleasePipelineMetadata());

// 	Mtl4AllocationMetadata* indicesMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(indicesGpu, true);
// 	if (indicesMetadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
// 	}
// 	defer (mtl4ReleaseAllocationMetadata());

// 	size_t indicesLength = indicesMetadata->size - mtl4GpuPtrOffsetFromBase(indicesMetadata, indicesGpu);

// 	Mtl4AllocationMetadata* argsGpuMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(argsGpu, true);
// 	if (argsGpuMetadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
// 	}
// 	defer (mtl4ReleaseAllocationMetadata());

// 	size_t argsGpuOffsetFromBase = mtl4GpuPtrOffsetFromBase(argsGpuMetadata, argsGpu);

// 	mtl4FlushCommandEncoderOf(metadata);
// 	[metadata->computeEncoder
// 		copyFromBuffer:argsGpuMetadata->buffer
// 		sourceOffset:argsGpuOffsetFromBase
// 		toBuffer:gMtl4CommandBufferStorage.indirectDrawArgsBuffer
// 		destinationOffset:metadata->indirectDrawArgsBufferOffset
// 		size:sizeof(GpuIndirectDrawArgs)
// 	];
// 	// [metadata->computeEncoder updateFence:fence afterEncoderStages:MTLStageBlit];
// 	[metadata->computeEncoder barrierAfterStages:MTLStageBlit beforeQueueStages:MTLStageVertex visibilityOptions:MTL4VisibilityOptionDevice];
// 	mtl4FlushCommandEncoderOf(metadata);

// 	[metadata->vertexArgumentTable setAddress:(uintptr_t)vertexDataGpu atIndex:0];

// 	[metadata->fragmentArgumentTable setAddress:(uintptr_t)pixelDataGpu atIndex:0];
// 	[metadata->fragmentArgumentTable setAddress:(uintptr_t)metadata->textureHeapPtr atIndex:1];

// 	// [metadata->renderEncoder barrierAfterQueueStages:MTLStageBlit beforeStages:MTLStageFragment visibilityOptions:MTL4VisibilityOptionDevice];
// 	// [metadata->renderEncoder waitForFence:fence beforeEncoderStages:MTLStageVertex];
// 	[metadata->renderEncoder setArgumentTable:metadata->vertexArgumentTable atStages:MTLStageVertex];
// 	[metadata->renderEncoder setArgumentTable:metadata->fragmentArgumentTable atStages:MTLStageFragment];
// 	[metadata->renderEncoder setRenderPipelineState:pipeline->graphics.pso];
// 	[metadata->renderEncoder
// 		drawIndexedPrimitives:gMtl4GpuTopologyToMtlPrimitive[pipeline->graphics.desc.topology]
// 		indexType:MTLIndexTypeUInt32
// 		indexBuffer:(uintptr_t)indicesGpu
// 		indexBufferLength:indicesLength
// 		indirectBuffer:[gMtl4CommandBufferStorage.indirectDrawArgsBuffer gpuAddress] + metadata->indirectDrawArgsBufferOffset
// 	];
// }

// bool mtl4AcquireResourcesForNewCommandBuffer(
// 	Mtl4CommandBuffer* handle,
// 	id<MTL4CommandQueue>* queue,
// 	id<MTL4CommandAllocator>* mtlAllocator,
// 	id<MTL4ArgumentTable>* computeArgumentTable,
// 	id<MTL4ArgumentTable>* vertexArgumentTable,
// 	id<MTL4ArgumentTable>* fragmentArgumentTable,
// 	id<MTLSharedEvent>* submitEvent,
// 	size_t* indirectDrawArgsOffset
// ) {
	
// 	CmnResult localResult;

// 	{
// 		CmnScopedWriteRWMutex guard(&gMtl4CommandBufferStorage.commandBuffersMutex);
// 		*handle = cmnInsert(&gMtl4CommandBufferStorage.commandBuffers, {}, &localResult);
// 	}

// 	if (localResult != CMN_SUCCESS) {
// 		// NOTE: If this occurs, we are out of resource slots.
// 		return false;
// 	}

// 	*queue		= gMtl4CommandBufferStorage.queues[handle->index];
// 	*mtlAllocator	= gMtl4CommandBufferStorage.commandAllocators[handle->index];
// 	*computeArgumentTable = gMtl4CommandBufferStorage.computeArgumentTables[handle->index];
// 	*vertexArgumentTable = gMtl4CommandBufferStorage.vertexArgumentTables[handle->index];
// 	*fragmentArgumentTable = gMtl4CommandBufferStorage.fragmentArgumentTables[handle->index];
// 	*submitEvent	= gMtl4CommandBufferStorage.submitEvents[handle->index];
// 	*indirectDrawArgsOffset = sizeof(MTLDrawIndexedPrimitivesIndirectArguments) * handle->index;

// 	return true;
// }

// void mtl4ReleaseCommandBufferResources(Mtl4CommandBuffer handle) {
// 	{
// 		CmnScopedWriteRWMutex guard(&gMtl4CommandBufferStorage.commandBuffersMutex);
// 		cmnRemove(&gMtl4CommandBufferStorage.commandBuffers, handle);
// 	}
// }

// void mtl4EnsureValidCommandBuffer(Mtl4CommandBufferMetadata* metadata) {
// 	if (metadata->commandBuffer == nil) {
// 		metadata->commandBuffer = [gMtl4Context.device newCommandBuffer];
// 		[metadata->commandBuffer beginCommandBufferWithAllocator:metadata->commandAllocator];
// 	}
// }

// void mtl4EnsureValidComputeEndoderFor(Mtl4CommandBufferMetadata* metadata) {
// 	mtl4EnsureValidCommandBuffer(metadata);
// 	if (metadata->computeEncoder == nil) {
// 		metadata->computeEncoder = [metadata->commandBuffer computeCommandEncoder];
// 	}
// }

// void mtl4FlushCommandEncoderOf(Mtl4CommandBufferMetadata* metadata) {
// 	if (metadata->computeEncoder != nil) {
// 		[metadata->computeEncoder endEncoding];
// 		metadata->computeEncoder = nil;
// 	}
// }

// void mtl4FlushCommandBuffer(Mtl4CommandBufferMetadata* metadata) {
// 	if (metadata->commandBuffer == nil) {
// 		return;
// 	}

// 	mtl4FlushCommandEncoderOf(metadata);
// 	[metadata->commandBuffer endCommandBuffer];

// 	[metadata->queue commit:&metadata->commandBuffer count:1];

// 	[metadata->commandBuffer release];
// 	metadata->commandBuffer = nil;
// }

// void mtl4PushDebugLabel(Mtl4CommandBufferMetadata* metadata, const char* label) {
// 	NSString* nsLabel = [[NSString alloc] initWithCString:label encoding:NSASCIIStringEncoding];
// 	defer ([nsLabel release]);

// 	mtl4EnsureValidCommandBuffer(metadata);
// 	[metadata->commandBuffer pushDebugGroup:nsLabel];
// }

// void mtl4PopDebugLabel(Mtl4CommandBufferMetadata* metadata) {
// 	[metadata->commandBuffer popDebugGroup];
// }

// void mtl4StartCommandBufferExecution(Mtl4CommandBufferMetadata* metadata) {
// 	assert(metadata->status == MTL4_COMMAND_BUFFER_SUBMITTED);

// 	uint64_t submitCount = cmnAtomicLoad(&gMtl4CommandBufferStorage.submitCount);
// 	[metadata->submitEvent setSignaledValue:submitCount];

// 	cmnAtomicAdd(&gMtl4CommandBufferStorage.submitCount, 1ULL);
// }

// void mtl4SubmitSingleBuffer(GpuQueue queue, GpuCommandBuffer commandBuffer, id<MTLSharedEvent> event, uint64_t value, GpuResult* result) {
// 	(void)queue;

// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(commandBuffer);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}

// 	if (cmnAtomicExchange(&metadata->status, MTL4_COMMAND_BUFFER_SUBMITTED) != MTL4_COMMAND_BUFFER_ENCODING) {
// 		// NOTE: Another thread submitted the command buffer. Double submit.
// 		CMN_SET_RESULT(result, GPU_ALREADY_SUBMITTED);
// 		return;
// 	}

// 	mtl4FlushCommandBuffer(metadata);
// 	if (event != nil) {
// 		[metadata->queue signalEvent:event value:value];
// 	}
// 	mtl4StartCommandBufferExecution(metadata);

// 	mtl4ReleaseCommandBufferResources(handle);
// }

// bool mtl4IsStageCompute(GpuStageFlags stage) {
// 	return GPU_STAGE_COMPUTE & stage || GPU_STAGE_TRANSFER & stage;
// }

// bool mtl4IsStageRender(GpuStageFlags stage) {
// 	return GPU_STAGE_PIXEL_SHADER & stage || GPU_STAGE_RASTER_COLOR_OUT & stage || GPU_STAGE_VERTEX_SHADER & stage;
// }

// bool mtl4CanImposeNormalMtlBarrierBetween(GpuStageFlags before, GpuStageFlags after, GpuHazardFlags hazards) {
// 	(void)hazards;

// 	bool cannotImpose = before & GPU_STAGE_PIXEL_SHADER ||
// 		before & GPU_STAGE_RASTER_COLOR_OUT ||
// 		after & GPU_STAGE_PIXEL_SHADER ||
// 		after & GPU_STAGE_RASTER_COLOR_OUT;
// 	return !cannotImpose;
// }

Mtl4CommandBufferMetadata* mtl4AcquireCommandBufferMetadataFrom(Mtl4CommandBuffer handle) {
	CmnScopedReadRWMutex guard(&gMtl4CommandBufferStorage.commandBuffersMutex);

	bool wasHandleValid;
	Mtl4CommandBufferMetadata* metadata = &cmnGet(&gMtl4CommandBufferStorage.commandBuffers, handle, &wasHandleValid);
	if (!wasHandleValid) {
		return nullptr;
	}

	return metadata;
}

