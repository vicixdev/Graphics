#ifndef MTL4_ENCODING_CONTEXT_H
#define MTL4_ENCODING_CONTEXT_H

#include <Metal/Metal.h>
#include <lib/metal4/context.h>
#include <lib/metal4/command.h>
#include <lib/metal4/allocation.h>
#include <lib/metal4/events.h>
#include <lib/metal4/semaphores.h>

typedef struct Mtl4CommandEmissionContext {
	// Atomic
	bool				inUse;

	id<MTL4CommandQueue>		queue;
	id<MTLSharedEvent>		submitEvent;
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

MTLStages mtl4GpuToMtlStage(GpuStageFlags stage);
MTL4VisibilityOptions mtl4GpuHazardsToMtlVisibilityOptions(GpuHazardFlags hazards);

inline void mtl4FlushComputeEncoder(Mtl4CommandEmissionContext* context) {
	if (context->computeEncoder != nil) {
		[context->computeEncoder endEncoding];
		context->computeEncoder = nil;
	}
	context->computeUsedStages = 0;
}

inline void mtl4FlushCommandBuffer(Mtl4CommandEmissionContext* context) {
	if (context->commandBuffer == nil) {
		return;
	}

	mtl4FlushComputeEncoder(context);
	[context->commandBuffer endCommandBuffer];

	[context->queue commit:&context->commandBuffer count:1];

	[context->commandBuffer release];
	context->commandBuffer = nil;
}


inline void mtl4EnsureValidCommandBuffer(Mtl4CommandEmissionContext* context) {
	if (context->commandBuffer == nil) {
		context->commandBuffer = [gMtl4Context.device newCommandBuffer];
		[context->commandBuffer beginCommandBufferWithAllocator:context->commandAllocator];
	}
}

inline void mtl4EnsureValidComputeEncoder(Mtl4CommandEmissionContext* context) {
	mtl4EnsureValidCommandBuffer(context);
	if (context->computeEncoder == nil) {
		context->computeEncoder = [context->commandBuffer computeCommandEncoder];
	}
}

inline size_t mtl4BumpAllocIn(Mtl4CommandEmissionContext* context, size_t size) {
	if (context->bumpBufferOffset + size > context->bumpBufferSize) {
		context->bumpBufferOffset = 0;
	}

	size_t offset = context->bumpBufferOffset;
	context->bumpBufferOffset += size;

	return offset;
}

inline void mtl4EmitBarrierForComputeStage(Mtl4CommandEmissionContext* context, GpuStageFlags before, MTLStages stage, GpuHazardFlags hazards) {
	if (before == 0) {
		return;
	}

	MTLStages mtlBefore = mtl4GpuToMtlStage(before);
	MTL4VisibilityOptions mtlVisibility = mtl4GpuHazardsToMtlVisibilityOptions(hazards);

	if (context->computeUsedStages & stage) {
		mtl4FlushComputeEncoder(context);
	}

	mtl4EnsureValidComputeEncoder(context);
	[context->computeEncoder
		barrierAfterQueueStages:mtlBefore
		beforeStages:stage
		visibilityOptions:mtlVisibility];
}

inline void mtl4EmitBlitBarrier(Mtl4CommandEmissionContext* context, GpuStageFlags before, GpuHazardFlags hazards) {
	mtl4EmitBarrierForComputeStage(context, before, MTLStageBlit, hazards);
}

inline void mtl4EmitDispatchBarrier(Mtl4CommandEmissionContext* context, GpuStageFlags before, GpuHazardFlags hazards) {
	mtl4EmitBarrierForComputeStage(context, before, MTLStageDispatch, hazards);
}

inline void mtl4EmitCopyBufferToBuffer(Mtl4CommandEmissionContext* context, const Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_COPY_BUFFER_TO_BUFFER);

	const Mtl4CommandCopyBufferToBuffer* copy = &command->copyBufferToBuffer;

	Mtl4AllocationMetadata* destinationMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(copy->destination, true);
	if (destinationMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* sourceMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(copy->source, true);
	if (sourceMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	size_t destinationOffset = mtl4GpuPtrOffsetFromBase(destinationMetadata, copy->destination);
	size_t sourceOffset = mtl4GpuPtrOffsetFromBase(sourceMetadata, copy->source);

	mtl4EnsureValidComputeEncoder(context);
	[context->computeEncoder
	 	copyFromBuffer:sourceMetadata->buffer sourceOffset:sourceOffset
		toBuffer:destinationMetadata->buffer destinationOffset:destinationOffset
		size:copy->size];

	context->computeUsedStages |= MTLStageBlit;

	CMN_SET_RESULT(result, GPU_SUCCESS);
	
}

inline void mtl4EmitDispatch(Mtl4CommandEmissionContext* context, const Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_DISPATCH);

	const Mtl4CommandDispatch* dispatch = &command->dispatch;

	Mtl4PipelineMetadata* pipelineMetadata = mtl4AcquirePipelineMetadataFrom(dispatch->pipeline);
	if (pipelineMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_PIPELINE_FOUND);
		return;
	}

	if (pipelineMetadata->type != MTL4_PIPELINE_COMPUTE) {
		CMN_SET_RESULT(result, GPU_INCOMPATIBLE_PIPELINE);
		return;
	}
	defer (mtl4ReleasePipelineMetadata());

	[context->computeArgumentTable setAddress:(uintptr_t)dispatch->data atIndex:0];

	mtl4EnsureValidComputeEncoder(context);
	[context->computeEncoder setComputePipelineState:pipelineMetadata->compute.pso];
	[context->computeEncoder setArgumentTable:context->computeArgumentTable];
	[context->computeEncoder
		dispatchThreadgroups:MTLSizeMake(dispatch->gridDimensions[0], dispatch->gridDimensions[1], dispatch->gridDimensions[2])
		threadsPerThreadgroup:MTLSizeMake(pipelineMetadata->compute.groupSize[0], pipelineMetadata->compute.groupSize[1], pipelineMetadata->compute.groupSize[2])];

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

inline void mtl4EmitDispatchIndirect(Mtl4CommandEmissionContext* context, const Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_DISPATCH_INDIRECT);

	const Mtl4CommandDispatchIndirect* dispatch = &command->dispatchIndirect;

	Mtl4PipelineMetadata* pipelineMetadata = mtl4AcquirePipelineMetadataFrom(dispatch->pipeline);
	if (pipelineMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_PIPELINE_FOUND);
		return;
	}

	if (pipelineMetadata->type != MTL4_PIPELINE_COMPUTE) {
		CMN_SET_RESULT(result, GPU_INCOMPATIBLE_PIPELINE);
		return;
	}
	defer (mtl4ReleasePipelineMetadata());

	[context->computeArgumentTable setAddress:(uintptr_t)dispatch->data atIndex:0];

	mtl4EnsureValidComputeEncoder(context);
	[context->computeEncoder setComputePipelineState:pipelineMetadata->compute.pso];
	[context->computeEncoder setArgumentTable:context->computeArgumentTable];
	[context->computeEncoder
		dispatchThreadgroupsWithIndirectBuffer:(uintptr_t)dispatch->indirectArgs
		threadsPerThreadgroup:MTLSizeMake(pipelineMetadata->compute.groupSize[0], pipelineMetadata->compute.groupSize[1], pipelineMetadata->compute.groupSize[2])];

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
	
}

inline void mtl4EmitSignal(Mtl4CommandEmissionContext* context, const Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_SIGNAL);

	GpuResult localResult;

	const Mtl4CommandSignal* signal = &command->signal;

	id<MTLEvent> event = mtl4AcquireOrCreateEventFor(signal->signal, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}
	defer (mtl4ReleaseEvent());

	Mtl4AllocationMetadata* ptrMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(signal->signal, true);
	if (ptrMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	size_t ptrOffsetFromBase = mtl4GpuPtrOffsetFromBase(ptrMetadata, signal->signal);

	size_t allocOffset = mtl4BumpAllocIn(context, sizeof(uint64_t));
	*(uint64_t*)((uintptr_t)[context->bumpBuffer contents] + allocOffset) = signal->value;

	mtl4EmitBlitBarrier(context, command->waitFor, command->waitingHazards);
	mtl4EnsureValidComputeEncoder(context);
	[context->computeEncoder
		copyFromBuffer:context->bumpBuffer
		sourceOffset:allocOffset
		toBuffer:ptrMetadata->buffer
		destinationOffset:ptrOffsetFromBase
		size:sizeof(uint64_t)];
	mtl4FlushCommandBuffer(context);

	[context->queue signalEvent:event value:signal->value];
}

inline void mtl4EmitWait(Mtl4CommandEmissionContext* context, const Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_WAIT);

	GpuResult localResult;

	const Mtl4CommandWait* wait = &command->wait;

	id<MTLEvent> event = mtl4AcquireOrCreateEventFor(wait->signal, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}
	defer (mtl4ReleaseEvent());

	Mtl4AllocationMetadata* ptrMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(wait->signal, true);
	if (ptrMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	mtl4FlushCommandBuffer(context);
	[context->queue waitForEvent:event value:wait->value];
}

inline void mtl4EmitCommand(Mtl4CommandEmissionContext* context, const Mtl4Command* command, GpuResult* result) {
	switch (command->type) {
		case MTL4_CMD_COPY_BUFFER_TO_BUFFER: {
			mtl4EmitBlitBarrier(context, command->waitFor, command->waitingHazards);
			mtl4EmitCopyBufferToBuffer(context, command, result);

			break;
		}
		case MTL4_CMD_DISPATCH: {
			mtl4EmitDispatchBarrier(context, command->waitFor, command->waitingHazards);
			mtl4EmitDispatch(context, command, result);

			break;
		}
		case MTL4_CMD_DISPATCH_INDIRECT: {
			mtl4EmitDispatchBarrier(context, command->waitFor, command->waitingHazards);
			mtl4EmitDispatchIndirect(context, command, result);

			break;
		}
		case MTL4_CMD_SIGNAL: {
			mtl4EmitSignal(context, command, result);
			break;
		}
		case MTL4_CMD_WAIT: {
			mtl4EmitWait(context, command, result);
			break;
		}
	}
}

inline void mtl4EmitSignal(
	Mtl4CommandEmissionContext* context,
	Mtl4Semaphore semaphore,
	uint64_t value,
	GpuResult* result
) {
	Mtl4SemaphoreMetadata* semaphoreMetadata = mtl4AcquireSemaphoreMetadataFrom(semaphore);
	if (semaphoreMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_SEMAPHORE_FOUND);
		return;
	}

	[context->queue
		signalEvent:semaphoreMetadata->event
		value:value];
}

inline MTLStages mtl4GpuToMtlStage(GpuStageFlags stage) {
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
		stages |= MTLStageFragment;
	}

	return stages;
}

inline MTL4VisibilityOptions mtl4GpuHazardsToMtlVisibilityOptions(GpuHazardFlags hazards) {
	MTL4VisibilityOptions options = MTL4VisibilityOptionDevice;

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

#endif // MTL4_ENCODING_CONTEXT_H

