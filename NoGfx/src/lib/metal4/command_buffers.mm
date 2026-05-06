#include "command_buffers.h"

#include <lib/common/heap_allocator.h>
#include <lib/common/atomic.h>
#include <lib/common/futex.h>
#include <lib/metal4/context.h>
#include <lib/metal4/tables.h>
#include <lib/metal4/allocation.h>
#include <lib/metal4/fences.h>
#include <lib/metal4/semaphores.h>

Mtl4CommandBufferStorage gMtl4CommandBufferStorage;

void mtl4InitCommandBufferStorage(GpuResult* result) {

	gMtl4CommandBufferStorage = {};

	cmnCreateStaticHandleMap(&gMtl4CommandBufferStorage.commandBuffers, {});

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		id<MTL4CommandAllocator> commandAllocator = [gMtl4Context.device newCommandAllocator];
		if (commandAllocator == nil) {
			CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
			return;
		}

		gMtl4CommandBufferStorage.commandAllocators[i] = commandAllocator;
	}

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		id<MTL4CommandQueue> queue = [gMtl4Context.device newMTL4CommandQueue];
		if (queue == nil) {
			CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
			return;
		}

		gMtl4CommandBufferStorage.queues[i] = queue;
		[queue addResidencySet:gMtl4AllocationStorage.residencySet];
		[queue addResidencySet:gMtl4EventStorage.uploadBufferResidencySet];
	}

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		id<MTLSharedEvent> event = [gMtl4Context.device newSharedEvent];
		if (event == nil) {
			CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
			return;
		}

		gMtl4CommandBufferStorage.submitEvents[i] = event;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4FiniCommandBufferStorage(void) {
	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		if (gMtl4CommandBufferStorage.commandAllocators[i] != nil) {
			[gMtl4CommandBufferStorage.commandAllocators[i] release];
		}
	}

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		if (gMtl4CommandBufferStorage.queues[i] != nil) {
			[gMtl4CommandBufferStorage.queues[i] release];
		}
	}

	gMtl4CommandBufferStorage = {};
	return;
}

GpuCommandBuffer mtl4StartCommandEncoding(GpuQueue queue, GpuResult* result) {
	(void)queue;

	Mtl4CommandBuffer handle;
	id<MTL4CommandQueue> mtlQueue;
	id<MTL4CommandAllocator> mtlAllocator;
	id<MTLSharedEvent> submitEvent;

	if (!mtl4AcquireResourcesForNewCommandBuffer(&handle, &mtlQueue, &mtlAllocator, &submitEvent)) {
		CMN_SET_RESULT(result, GPU_TOO_MANY_UNSUBMITTED_COMMAND_BUFFERS);
		return {};
	}

	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	assert(metadata != nullptr);

	metadata->status = MTL4_COMMAND_BUFFER_ENCODING;
	metadata->queue = mtlQueue;
	metadata->submitEvent = submitEvent;
	metadata->commandAllocator = mtlAllocator;

	metadata->commandBuffer = [gMtl4Context.device newCommandBuffer];
	[metadata->commandBuffer beginCommandBufferWithAllocator:mtlAllocator];

	metadata->computeEncoder = [metadata->commandBuffer computeCommandEncoder];

	uint64_t submitCount = cmnAtomicLoad(&gMtl4CommandBufferStorage.submitCount);
	[metadata->queue waitForEvent:submitEvent value:submitCount];

	[gMtl4AllocationStorage.residencySet commit];

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return mtl4HandleToGpuCommandBuffer(handle);
}

void mtl4Submit(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result) {
	for (size_t i = 0; i < commandBufferCount; i++) {
		mtl4SubmitSingleBuffer(queue, commandBuffers[i], nullptr, 0, result);
	}
}

void mtl4SubmitWithSignal(
	GpuQueue queue,
	GpuCommandBuffer* commandBuffers,
	size_t commandBufferCount,
	GpuSemaphore semaphore,
	uint64_t value,
	GpuResult* result
) {
	Mtl4Semaphore semaphoreHandle = mtl4GpuSemaphoreToHandle(semaphore);
	Mtl4SemaphoreMetadata* semaphoreMetadata = mtl4AcquireSemaphoreMetadataFrom(semaphoreHandle);
	if (semaphoreMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_SEMAPHORE_FOUND);
		return;
	}

	for (size_t i = 0; i < (commandBufferCount - 1); i++) {
		mtl4SubmitSingleBuffer(queue, commandBuffers[i], 0, 0, result);
	}
	mtl4SubmitSingleBuffer(queue, commandBuffers[commandBufferCount - 1], semaphoreMetadata, value, result);
}
void mtl4MemCpy(GpuCommandBuffer cb, void* destGpu, void* srcGpu, size_t size, GpuResult* result) {
	GpuResult localResult;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4GpuAddress destination = mtl4PtrToGpuAddress(destGpu);
	Mtl4GpuAddress source = mtl4PtrToGpuAddress(srcGpu);

	Mtl4AllocationMetadata* destinationMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(destination);
	if (destinationMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* sourceMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(source);
	if (sourceMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	mtl4EnsureBackingBufferIsAllocated(destination, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}

	// NOTE: Let's assume that the source buffer is committed. The validation layer will ensure this.
	[metadata->computeEncoder
	 	copyFromBuffer:sourceMetadata->buffer sourceOffset:source.offset
		toBuffer:destinationMetadata->buffer destinationOffset:destination.offset
		size:size];

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4CopyToTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result) {
	(void)destGpu;
	
	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4GpuAddress source = mtl4PtrToGpuAddress(srcGpu);
	Mtl4AllocationMetadata* sourceMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(source);
	if (sourceMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4Texture textureHandle = mtl4GpuTextureToHadle(texture);
	Mtl4TextureMetadata* textureMetadata = mtl4AcquireTextureMetadataFrom(textureHandle);
	if (textureMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_TEXTURE_FOUND);
		return;
	}
	defer (mtl4ReleaseTextureMetadata());

	// TODO: Support arrays.
	if (textureMetadata->descriptor.type == GPU_TEXTURE_2D_ARRAY ||
		textureMetadata->descriptor.type == GPU_TEXTURE_CUBE_ARRAY
	) {
		assert(false && "Unimplemented");
	}

	MTLSize textureSize = MTLSizeMake(
		textureMetadata->descriptor.dimensions[0],
		textureMetadata->descriptor.dimensions[1],
		textureMetadata->descriptor.dimensions[2]
	);
	size_t bytesPerRow = textureMetadata->descriptor.dimensions[0] * gMtl4GpuFormatPixelSize[textureMetadata->descriptor.format];
	size_t bytesPerImage = textureMetadata->descriptor.dimensions[0] *
				textureMetadata->descriptor.dimensions[1] *
				textureMetadata->descriptor.dimensions[2] *
				gMtl4GpuFormatPixelSize[textureMetadata->descriptor.format];

	// TODO: Support mipmaps.
	[metadata->computeEncoder copyFromBuffer:sourceMetadata->buffer
	 	sourceOffset:source.offset
		sourceBytesPerRow:bytesPerRow
		sourceBytesPerImage:bytesPerImage
		sourceSize:textureSize
		toTexture:textureMetadata->texture
		destinationSlice:0
		destinationLevel:0
		destinationOrigin:MTLOriginMake(0, 0, 0)];

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4CopyFromTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result) {
	(void)srcGpu;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4GpuAddress destination = mtl4PtrToGpuAddress(destGpu);
	Mtl4AllocationMetadata* destinationMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(destination);
	if (destinationMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4Texture textureHandle = mtl4GpuTextureToHadle(texture);
	Mtl4TextureMetadata* textureMetadata = mtl4AcquireTextureMetadataFrom(textureHandle);
	if (textureMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_TEXTURE_FOUND);
		return;
	}
	defer (mtl4ReleaseTextureMetadata());

	// TODO: Support arrays.
	if (textureMetadata->descriptor.type == GPU_TEXTURE_2D_ARRAY ||
		textureMetadata->descriptor.type == GPU_TEXTURE_CUBE_ARRAY
	) {
		assert(false && "Unimplemented");
	}

	MTLSize textureSize = MTLSizeMake(
		textureMetadata->descriptor.dimensions[0],
		textureMetadata->descriptor.dimensions[1],
		textureMetadata->descriptor.dimensions[2]
	);
	size_t bytesPerRow = textureMetadata->descriptor.dimensions[0] * gMtl4GpuFormatPixelSize[textureMetadata->descriptor.format];
	size_t bytesPerImage = textureMetadata->descriptor.dimensions[0] *
				textureMetadata->descriptor.dimensions[1] *
				textureMetadata->descriptor.dimensions[2] *
				gMtl4GpuFormatPixelSize[textureMetadata->descriptor.format];

	// TODO: Support mipmaps.
	[metadata->computeEncoder copyFromTexture:textureMetadata->texture
		sourceSlice:0
		sourceLevel:0
		sourceOrigin:MTLOriginMake(0, 0, 0)
		sourceSize:textureSize
		toBuffer:destinationMetadata->buffer
		destinationOffset:destination.offset
		destinationBytesPerRow:bytesPerRow
		destinationBytesPerImage:bytesPerImage
	];

}

void mtl4Barrier(GpuCommandBuffer cb, GpuStage before, GpuStage after, GpuHazardFlags hazards, GpuResult* result) {
	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	MTLStages metalBefore = mtl4GpuToMtlStage(before);
	MTLStages metalAfter = mtl4GpuToMtlStage(after);
	MTL4VisibilityOptions metalVisibilityOptions = mtl4GpuHazardsToMtlVisibilityOptions(hazards);

	// TODO: Figure out render stuff...

	if (mtl4IsStageCompute(before)) {
		[metadata->computeEncoder endEncoding];
		metadata->computeEncoder = [metadata->commandBuffer computeCommandEncoder];
	}
	if (mtl4IsStageRender(before)) {
		assert(false && "Unimplemented.");
	}

	if (mtl4IsStageCompute(after)) {
		[metadata->computeEncoder barrierAfterQueueStages:metalBefore beforeStages:metalAfter visibilityOptions:metalVisibilityOptions];
	}
	if (mtl4IsStageRender(after)) {
		assert(false && "Unimplemented.");
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4SignalAfter(GpuCommandBuffer cb, GpuStage before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result) {
	assert(signal == GPU_SIGNAL_ATOMIC_MAX && "The only supported signal operation is GPU_SIGNAL_ATOMIC_MAX.");

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	mtl4SignalEvent(metadata, before, ptrGpu, value, result);
}

void mtl4WaitBefore(GpuCommandBuffer cb, GpuStage after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result) {
	(void)hazards;
	assert(op == GPU_OP_GREATER_EQUAL && "The only supported wait operation is GPU_OP_GREATER_EQUAL.");
	assert(mask == ~(uint64_t)0 && "The only supported mask is ~0.");

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	mtl4WaitEvent(metadata, after, ptrGpu, value, result);
}

bool mtl4AcquireResourcesForNewCommandBuffer(Mtl4CommandBuffer* handle, id<MTL4CommandQueue>* queue, id<MTL4CommandAllocator>* mtlAllocator, id<MTLSharedEvent>* submitEvent) {
	
	CmnResult localResult;

	{
		CmnScopedWriteRWMutex guard(&gMtl4CommandBufferStorage.commandBuffersMutex);
		*handle = cmnInsert(&gMtl4CommandBufferStorage.commandBuffers, {}, &localResult);
	}

	if (localResult != CMN_SUCCESS) {
		// NOTE: If this occurs, we are out of resource slots.
		return false;
	}

	*queue		= gMtl4CommandBufferStorage.queues[handle->index];
	*mtlAllocator	= gMtl4CommandBufferStorage.commandAllocators[handle->index];
	*submitEvent	= gMtl4CommandBufferStorage.submitEvents[handle->index];

	return true;
}

void mtl4ReleaseCommandBufferResources(Mtl4CommandBuffer handle) {
	{
		CmnScopedWriteRWMutex guard(&gMtl4CommandBufferStorage.commandBuffersMutex);
		cmnRemove(&gMtl4CommandBufferStorage.commandBuffers, handle);
	}
}

void mtl4SubmitSingleBuffer(GpuQueue queue, GpuCommandBuffer commandBuffer, Mtl4SemaphoreMetadata* semaphore, uint64_t value, GpuResult* result) {
	(void)queue;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(commandBuffer);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	if (cmnAtomicExchange(&metadata->status, MTL4_COMMAND_BUFFER_SUBMITTED) != MTL4_COMMAND_BUFFER_ENCODING) {
		// NOTE: Another thread submitted the command buffer. Double submit.
		CMN_SET_RESULT(result, GPU_ALREADY_SUBMITTED);
		return;
	}

	if (metadata->computeEncoder != nil) {
		[metadata->computeEncoder endEncoding];
	}
	if (metadata->renderEncoder != nil) {
		[metadata->renderEncoder endEncoding];
	}
	[metadata->commandBuffer endCommandBuffer];

	[metadata->queue commit:&metadata->commandBuffer count:1];

	if (semaphore != nullptr) {
		[metadata->queue signalEvent:semaphore->event value:value];
	}

	uint64_t submitCount = cmnAtomicLoad(&gMtl4CommandBufferStorage.submitCount);
	[metadata->submitEvent setSignaledValue:submitCount];

	cmnAtomicAdd(&gMtl4CommandBufferStorage.submitCount, 1ULL);

	[metadata->commandBuffer release];

	mtl4ReleaseCommandBufferResources(handle);
}

// void mtl4SubmitRaw(
// 	GpuQueue queue,
// 	GpuCommandBuffer* commandBuffers,
// 	size_t commandBufferCount,
// 	GpuSemaphore semaphore,
// 	uint64_t value,
// 	GpuResult* result
// ) {
// 	(void)queue;

// 	CmnResult localResult;

// 	CMN_SET_RESULT(result, GPU_SUCCESS);

// 	id<MTL4CommandQueue> metalQueue = mtl4Queue();

// 	// TODO: Switch thread local arena.
// 	id<MTL4CommandBuffer>* metalCommandBuffers = cmnHeapAlloc<id<MTL4CommandBuffer>>(commandBufferCount + 1, &localResult);
// 	defer (cmnHeapFree(metalCommandBuffers));
// 	size_t validCommandBufferCount = 0;

// 	for (size_t i = 0; i < commandBufferCount; i++) {
// 		GpuCommandBuffer commandBuffer = commandBuffers[i];
// 		Mtl4CommandBuffer commandBufferHandle = mtl4GpuCommandBufferToHandle(commandBuffer);

// 		Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(commandBufferHandle);
// 		if (metadata == nullptr) {
// 			CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 			continue;
// 		}
// 		defer (mtl4ReleaseCommandBufferMetadata());

// 		if (metadata->status != MTL4_COMMAND_BUFFER_ENCODING) {
// 			CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
// 			continue;
// 		}
// 		metadata->status = MTL4_COMMAND_BUFFER_SUBMITTED;

// 		[metadata->computeEncoder endEncoding];
// 		[metadata->commandBuffer endCommandBuffer];

// 		metalCommandBuffers[validCommandBufferCount] = metadata->commandBuffer;
// 		validCommandBufferCount++;
// 	}

// 	if (validCommandBufferCount > 0) {
// 		[metalQueue addResidencySet:gMtl4AllocationStorage.residencySet];
// 		[metalQueue commit:metalCommandBuffers count:validCommandBufferCount];
// 	}

// 	if (semaphore != 0) {
// 		Mtl4Semaphore semaphoreHandle = mtl4GpuSemaphoreToHandle(semaphore);
// 		Mtl4SemaphoreMetadata* metadata = mtl4AcquireSemaphoreMetadataFrom(semaphoreHandle);
// 		if (metadata == nullptr) {
// 			CMN_SET_RESULT(result, GPU_NO_SUCH_SEMAPHORE_FOUND);
// 			return;
// 		}
// 		defer (mtl4ReleaseSemaphoreMetadata());

// 		[metalQueue signalEvent:metadata->event value:value];
// 	}

// 	// NOTE: Result here is GPU_SUCCESS if all the command buffers were valid.
// 	return;
// }

// void mtl4Submit(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result) {
// 	mtl4SubmitRaw(queue, commandBuffers, commandBufferCount, 0, 0, result);
// }

// void mtl4SubmitWithSignal(
// 	GpuQueue queue,
// 	GpuCommandBuffer* commandBuffers,
// 	size_t commandBufferCount,
// 	GpuSemaphore semaphore,
// 	uint64_t value,
// 	GpuResult* result
// ) {
// 	mtl4SubmitRaw(queue, commandBuffers, commandBufferCount, semaphore, value, result);
// }


// void mtl4SetActiveTextureHeapPtr(GpuCommandBuffer cb, void *ptrGpu, GpuResult* result) {
// 	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
// 	if (metadata == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
// 		return;
// 	}
// 	defer (mtl4ReleaseCommandBufferMetadata());

// 	CMN_SET_RESULT(result, GPU_SUCCESS);
// 	// metadata->boundTextureHeap = ptrGpu;
// }

// Mtl4CommandBuffer mtl4CreateCommandBuffer(GpuResult* result) {
// 	CmnResult localResult;

// 	Mtl4CommandBufferMetadata metadata = {};

// 	metadata.commandBuffer = [gMtl4Context.device newCommandBuffer];
// 	if (metadata.commandBuffer == nil) {
// 		CMN_SET_RESULT(result, GPU_COUND_NOT_CREATE_COMMAND_BUFFER);
// 		return {};
// 	}

// 	id<MTL4CommandAllocator> commandAllocator = [gMtl4Context.device newCommandAllocator];
// 	[metadata.commandBuffer beginCommandBufferWithAllocator:commandAllocator];

// 	metadata.computeEncoder = [metadata.commandBuffer computeCommandEncoder];
// 	if (metadata.computeEncoder == nil) {
// 		[metadata.commandBuffer endCommandBuffer];
// 		[metadata.commandBuffer release];

// 		CMN_SET_RESULT(result, GPU_COUND_NOT_CREATE_COMMAND_BUFFER);
// 		return {};
// 	}

// 	{
// 		CmnScopedStorageSyncLockWrite guard(&gMtl4CommandBufferStorage.sync);

// 		Mtl4CommandBuffer handle = cmnInsert(&gMtl4CommandBufferStorage.commandBuffers, metadata, &localResult);
// 		if (localResult != CMN_SUCCESS) {
// 			[metadata.computeEncoder release];
// 			[metadata.commandBuffer endCommandBuffer];
// 			[metadata.commandBuffer release];

// 			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
// 			return {};
// 		}

// 		CMN_SET_RESULT(result, GPU_SUCCESS);
// 		return handle;
// 	}
// }

// void mtl4DestroyCommandBuffer(Mtl4CommandBuffer commandBuffer) {
// 	bool wasHandleValid;
// 	Mtl4CommandBufferMetadata* metadata = &cmnGet(&gMtl4CommandBufferStorage.commandBuffers, commandBuffer, &wasHandleValid);
// 	if (!wasHandleValid) {
// 		return;
// 	}

// 	if (metadata->status != MTL4_COMMAND_BUFFER_SUBMITTED) {
// 		return;
// 	}

// 	[metadata->commandBuffer release];

// 	cmnRemove(&gMtl4CommandBufferStorage.commandBuffers, commandBuffer);
// }

// bool mtl4IsCommandBufferScheduledForDeletion(Mtl4CommandBuffer commandBuffer) {
// 	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(commandBuffer);
// 	if (metadata == nil) {
// 		return false;
// 	}

// 	return metadata->status == MTL4_COMMAND_BUFFER_SUBMITTED;
// }

bool mtl4IsStageCompute(GpuStage stage) {
	return GPU_STAGE_COMPUTE & stage || GPU_STAGE_TRANSFER & stage;
}

bool mtl4IsStageRender(GpuStage stage) {
	return GPU_STAGE_PIXEL_SHADER & stage || GPU_STAGE_RASTER_COLOR_OUT & stage || GPU_STAGE_VERTEX_SHADER & stage;
}

bool mtl4CanImposeNormalMtlBarrierBetween(GpuStage before, GpuStage after, GpuHazardFlags hazards) {
	(void)hazards;

	bool cannotImpose = before & GPU_STAGE_PIXEL_SHADER ||
		before & GPU_STAGE_RASTER_COLOR_OUT ||
		after & GPU_STAGE_PIXEL_SHADER ||
		after & GPU_STAGE_RASTER_COLOR_OUT;
	return !cannotImpose;
}

MTLStages mtl4GpuToMtlStage(GpuStage stage) {
	MTLStages stages = 0;

	if (stage & GPU_STAGE_TRANSFER) {
		stages |= MTLStageBlit;
	}
	if (stage & GPU_STAGE_COMPUTE) {
		stages |= MTLStageDispatch;
	}
	if (stage & GPU_STAGE_VERTEX_SHADER) {
		stages |= MTLStageVertex;
	}
	if (stage & GPU_STAGE_PIXEL_SHADER) {
		stages |= MTLStageFragment;
	}
	if (stage & GPU_STAGE_RASTER_COLOR_OUT) {
		stages |= MTLStageTile;
	}

	return stages;
}

MTL4VisibilityOptions mtl4GpuHazardsToMtlVisibilityOptions(GpuHazardFlags hazards) {
	MTL4VisibilityOptions options = MTL4VisibilityOptionNone;

	if (hazards & GPU_HAZARD_DESCRIPTORS) {
		options |= MTL4VisibilityOptionResourceAlias;
	}
	if (hazards & GPU_HAZARD_DRAW_ARGUMENTS) {
		options |= MTL4VisibilityOptionResourceAlias;
	}
	if (hazards & GPU_HAZARD_DEPTH_STENCIL) {
		options |= MTL4VisibilityOptionDevice;
	}

	return options;
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

