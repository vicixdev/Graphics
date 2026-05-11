#include "command_buffers.h"

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

	MTL4ArgumentTableDescriptor* computeArgumentTableDesc = [MTL4ArgumentTableDescriptor new];
	defer ([computeArgumentTableDesc release]);
	computeArgumentTableDesc.maxBufferBindCount = 1;
	computeArgumentTableDesc.maxSamplerStateBindCount = 0;
	computeArgumentTableDesc.maxTextureBindCount = 0;

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		id<MTL4ArgumentTable> argumentTable = [gMtl4Context.device
			newArgumentTableWithDescriptor:computeArgumentTableDesc
			error:nullptr];
		if (argumentTable == nil) {
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return;
		}

		gMtl4CommandBufferStorage.computeArgumentTables[i] = argumentTable;
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

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		if (gMtl4CommandBufferStorage.computeArgumentTables[i] != nil) {
			[gMtl4CommandBufferStorage.computeArgumentTables[i] release];
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
	id<MTL4ArgumentTable> computeArgumentTable;

	if (!mtl4AcquireResourcesForNewCommandBuffer(&handle, &mtlQueue, &mtlAllocator, &computeArgumentTable, &submitEvent)) {
		CMN_SET_RESULT(result, GPU_TOO_MANY_UNSUBMITTED_COMMAND_BUFFERS);
		return {};
	}

	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	assert(metadata != nullptr);

	metadata->status = MTL4_COMMAND_BUFFER_ENCODING;
	metadata->queue = mtlQueue;
	metadata->submitEvent = submitEvent;
	metadata->commandAllocator = mtlAllocator;
	metadata->computeArgumentTable = computeArgumentTable;

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

	for (size_t i = 0; i < commandBufferCount; i++) {
		mtl4SubmitSingleBuffer(queue, commandBuffers[i], semaphoreMetadata->events[i], value, result);
	}
	semaphoreMetadata->lastSignalCount = commandBufferCount;
}
void mtl4MemCpy(GpuCommandBuffer cb, void* destGpu, void* srcGpu, size_t size, GpuResult* result) {

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4AllocationMetadata* destinationMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(destGpu, true);
	if (destinationMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* sourceMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(srcGpu, true);
	if (sourceMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	size_t destinationOffset = mtl4GpuPtrOffsetFromBase(destinationMetadata, destGpu);
	size_t sourceOffset = mtl4GpuPtrOffsetFromBase(sourceMetadata, srcGpu);

	mtl4EnsureValidComputeEndoderFor(metadata);
	[metadata->computeEncoder
	 	copyFromBuffer:sourceMetadata->buffer sourceOffset:destinationOffset
		toBuffer:destinationMetadata->buffer destinationOffset:sourceOffset
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

	Mtl4AllocationMetadata* sourceMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(srcGpu, true);
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

	size_t sourceOffset = mtl4GpuPtrOffsetFromBase(sourceMetadata, srcGpu);

	// TODO: Support mipmaps.
	mtl4EnsureValidComputeEndoderFor(metadata);
	[metadata->computeEncoder copyFromBuffer:sourceMetadata->buffer
	 	sourceOffset:sourceOffset
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

	Mtl4AllocationMetadata* destinationMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(destGpu, true);
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

	size_t destinationOffset = mtl4GpuPtrOffsetFromBase(destinationMetadata, destGpu);

	// TODO: Support mipmaps.
	mtl4EnsureValidComputeEndoderFor(metadata);
	[metadata->computeEncoder copyFromTexture:textureMetadata->texture
		sourceSlice:0
		sourceLevel:0
		sourceOrigin:MTLOriginMake(0, 0, 0)
		sourceSize:textureSize
		toBuffer:destinationMetadata->buffer
		destinationOffset:destinationOffset
		destinationBytesPerRow:bytesPerRow
		destinationBytesPerImage:bytesPerImage
	];

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
		mtl4FlushCommandEncoderOf(metadata);
	}

	if (mtl4IsStageCompute(after)) {
		mtl4EnsureValidComputeEndoderFor(metadata);
		[metadata->computeEncoder
			barrierAfterQueueStages:metalBefore
			beforeStages:metalAfter & (MTLStageBlit | MTLStageDispatch)
			visibilityOptions:metalVisibilityOptions];
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

void mtl4Dispatch(GpuCommandBuffer cb, void* dataGpu, uint32_t gridDimensions[3], GpuResult* result) {

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return;
	}

	Mtl4PipelineMetadata* pipelineMetadata = mtl4AcquirePipelineMetadataFrom(metadata->pipeline);
	if (pipelineMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_PIPELINE_FOUND);
		return;
	}

	if (pipelineMetadata->type != MTL4_PIPELINE_COMPUTE) {
		CMN_SET_RESULT(result, GPU_INCOMPATIBLE_PIPELINE);
		return;
	}
	defer (mtl4ReleasePipelineMetadata());

	Mtl4AllocationMetadata* allocationMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(dataGpu, true);
	if (allocationMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	size_t gpuPointerOffset = mtl4GpuPtrOffsetFromBase(allocationMetadata, dataGpu);

	MTLGPUAddress baseGpuAddress = [allocationMetadata->buffer gpuAddress] + gpuPointerOffset;
	[metadata->computeArgumentTable setAddress:baseGpuAddress atIndex:0];

	mtl4EnsureValidComputeEndoderFor(metadata);
	[metadata->computeEncoder setComputePipelineState:pipelineMetadata->compute.pso];
	[metadata->computeEncoder setArgumentTable:metadata->computeArgumentTable];
	// TODO: Get groupSize from the pipeline... In some way...
	[metadata->computeEncoder
		dispatchThreadgroups:MTLSizeMake(gridDimensions[0], gridDimensions[1], gridDimensions[2])
		threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

bool mtl4AcquireResourcesForNewCommandBuffer(
	Mtl4CommandBuffer* handle,
	id<MTL4CommandQueue>* queue,
	id<MTL4CommandAllocator>* mtlAllocator,
	id<MTL4ArgumentTable>* computeArgumentTable,
	id<MTLSharedEvent>* submitEvent
) {
	
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
	*computeArgumentTable = gMtl4CommandBufferStorage.computeArgumentTables[handle->index];
	*submitEvent	= gMtl4CommandBufferStorage.submitEvents[handle->index];

	return true;
}

void mtl4ReleaseCommandBufferResources(Mtl4CommandBuffer handle) {
	{
		CmnScopedWriteRWMutex guard(&gMtl4CommandBufferStorage.commandBuffersMutex);
		cmnRemove(&gMtl4CommandBufferStorage.commandBuffers, handle);
	}
}

void mtl4EnsureValidCommandBuffer(Mtl4CommandBufferMetadata* metadata) {
	if (metadata->commandBuffer == nil) {
		metadata->commandBuffer = [gMtl4Context.device newCommandBuffer];
		[metadata->commandBuffer beginCommandBufferWithAllocator:metadata->commandAllocator];
	}
}

void mtl4EnsureValidComputeEndoderFor(Mtl4CommandBufferMetadata* metadata) {
	mtl4EnsureValidCommandBuffer(metadata);
	if (metadata->computeEncoder == nil) {
		metadata->computeEncoder = [metadata->commandBuffer computeCommandEncoder];
	}
}

void mtl4FlushCommandEncoderOf(Mtl4CommandBufferMetadata* metadata) {
	if (metadata->computeEncoder != nil) {
		[metadata->computeEncoder endEncoding];
		metadata->computeEncoder = nil;
	}
}

void mtl4FlushCommandBuffer(Mtl4CommandBufferMetadata* metadata) {
	if (metadata->commandBuffer == nil) {
		return;
	}

	mtl4FlushCommandEncoderOf(metadata);
	[metadata->commandBuffer endCommandBuffer];

	[metadata->queue commit:&metadata->commandBuffer count:1];

	[metadata->commandBuffer release];
	metadata->commandBuffer = nil;
}

void mtl4PushDebugLabel(Mtl4CommandBufferMetadata* metadata, const char* label) {
	NSString* nsLabel = [[NSString alloc] initWithCString:label encoding:NSASCIIStringEncoding];
	defer ([nsLabel release]);

	mtl4EnsureValidCommandBuffer(metadata);
	[metadata->commandBuffer pushDebugGroup:nsLabel];
}

void mtl4PopDebugLabel(Mtl4CommandBufferMetadata* metadata) {
	[metadata->commandBuffer popDebugGroup];
}

void mtl4StartCommandBufferExecution(Mtl4CommandBufferMetadata* metadata) {
	assert(metadata->status == MTL4_COMMAND_BUFFER_SUBMITTED);

	uint64_t submitCount = cmnAtomicLoad(&gMtl4CommandBufferStorage.submitCount);
	[metadata->submitEvent setSignaledValue:submitCount];

	cmnAtomicAdd(&gMtl4CommandBufferStorage.submitCount, 1ULL);
}

void mtl4SubmitSingleBuffer(GpuQueue queue, GpuCommandBuffer commandBuffer, id<MTLSharedEvent> event, uint64_t value, GpuResult* result) {
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

	mtl4FlushCommandBuffer(metadata);
	if (event != nil) {
		[metadata->queue signalEvent:event value:value];
	}
	mtl4StartCommandBufferExecution(metadata);

	mtl4ReleaseCommandBufferResources(handle);
}

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

