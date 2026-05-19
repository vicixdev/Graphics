#include "command_emission.h"

#include <lib/metal4/context.h>
#include <lib/metal4/allocation.h>
#include <lib/metal4/textures.h>
#include <lib/metal4/events.h>
#include <lib/metal4/tables.h>
#include <lib/metal4/queue.h>
#include <lib/metal4/shader/acquire_icb_range.h>
#include <lib/metal4/shader/prep_multidrawindirect.h>

void mtl4InitCommandEmissionContext(Mtl4CommandEmissionContext* context, Mtl4QueueMetadata* queue, GpuResult* result) {
	context->bumpBuffer = [gMtl4Context.device
		newBufferWithLength:1024*1024
		options:MTLResourceStorageModeShared | MTLResourceCPUCacheModeWriteCombined
	];
	if (context->bumpBuffer == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
	}
	context->bumpBufferSize = 1024 * 1024;
	mtl4AddAllocationToResidencySet(context->bumpBuffer);


	context->commandAllocator = [gMtl4Context.device newCommandAllocator];
	if (context->commandAllocator == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
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

	context->computeArgumentTable = [gMtl4Context.device
		newArgumentTableWithDescriptor:computeArgumentTableDesc
		error:nullptr];
	if (context->computeArgumentTable == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	context->vertexArgumentTable = [gMtl4Context.device
		newArgumentTableWithDescriptor:vertexArgumentTableDesc
		error:nullptr];
	if (context->vertexArgumentTable == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	context->fragmentArgumentTable = [gMtl4Context.device
		newArgumentTableWithDescriptor:fragmentArgumentTableDesc
		error:nullptr];
	if (context->fragmentArgumentTable == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}


	MTLIndirectCommandBufferDescriptor* icbDesc = [[MTLIndirectCommandBufferDescriptor new] autorelease];
	icbDesc.commandTypes = MTLIndirectCommandTypeDrawIndexed;
	icbDesc.inheritCullMode = YES;
	icbDesc.inheritDepthStencilState = YES;
	icbDesc.inheritDepthBias = YES;
	icbDesc.inheritDepthClipMode = YES;
	icbDesc.inheritPipelineState = YES;
	icbDesc.inheritFrontFacingWinding = YES;
	icbDesc.inheritTriangleFillMode = YES;
	icbDesc.inheritBuffers = NO;
	icbDesc.maxVertexBufferBindCount = 1;
	icbDesc.maxFragmentBufferBindCount = 2;

	context->icbBuffer = [gMtl4Context.device
		newIndirectCommandBufferWithDescriptor:icbDesc
		maxCommandCount:MTL4_MAX_MULTIDRAW_ARG_COUNT * MTL4_MAX_MULTIDRAW_CALLS
		options:MTLResourceStorageModePrivate];
	if (context->icbBuffer == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
	}
	mtl4AddAllocationToResidencySet(context->icbBuffer);

	context->firstFreeIcbIndex = [gMtl4Context.device
		newBufferWithLength:sizeof(uint32_t)
		options:MTLResourceStorageModePrivate];
	if (context->firstFreeIcbIndex == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
	}
	mtl4AddAllocationToResidencySet(context->firstFreeIcbIndex);


	context->queue = queue->queue;


	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4FiniCommandEmissionContext(Mtl4CommandEmissionContext* context) {
	if (context->bumpBuffer != nil) {
		[context->bumpBuffer release];
	}

	if (context->commandAllocator != nil) {
		[context->commandAllocator release];
	}

	if (context->computeArgumentTable != nil) {
		[context->computeArgumentTable release];
	}

	if (context->vertexArgumentTable != nil) {
		[context->vertexArgumentTable release];
	}

	if (context->fragmentArgumentTable != nil) {
		[context->fragmentArgumentTable release];
	}

	if (context->firstFreeIcbIndex != nil) {
		[context->firstFreeIcbIndex release];
	}

	if (context->icbBuffer != nil) {
		[context->icbBuffer release];
	}

}

void mtl4FlushComputeEncoder(Mtl4CommandEmissionContext* context) {
	if (context->computeEncoder != nil) {
		[context->computeEncoder endEncoding];
		context->computeEncoder = nil;
	}
	context->computeUsedStages = 0;
}

void mtl4FlushCommandBuffer(Mtl4CommandEmissionContext* context) {
	if (context->commandBuffer == nil) {
		return;
	}

	mtl4FlushComputeEncoder(context);
	[context->commandBuffer endCommandBuffer];

	[gMtl4Context.residencySet commit];
	[context->queue commit:&context->commandBuffer count:1];

	[context->commandBuffer release];
	context->commandBuffer = nil;
}


void mtl4EnsureValidCommandBuffer(Mtl4CommandEmissionContext* context) {
	if (context->commandBuffer == nil) {
		context->commandBuffer = [gMtl4Context.device newCommandBuffer];
		[context->commandBuffer beginCommandBufferWithAllocator:context->commandAllocator];
	}
}

void mtl4EnsureValidComputeEncoder(Mtl4CommandEmissionContext* context) {
	mtl4EnsureValidCommandBuffer(context);
	if (context->computeEncoder == nil) {
		context->computeEncoder = [context->commandBuffer computeCommandEncoder];
	}
}

size_t mtl4BumpAllocIn(Mtl4CommandEmissionContext* context, size_t size) {
	if (context->bumpBufferOffset + size > context->bumpBufferSize) {
		context->bumpBufferOffset = 0;
	}

	size_t offset = context->bumpBufferOffset;
	context->bumpBufferOffset += size;

	return offset;
}

void mtl4EmitBarrierForComputeStage(Mtl4CommandEmissionContext* context, GpuStageFlags before, MTLStages stage, GpuHazardFlags hazards) {
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

void mtl4EmitRenderpassBarriers(Mtl4CommandEmissionContext* context, Mtl4Command* command) {
	assert(command->type == MTL4_CMD_RENDERPASS);

	if (!command->renderPass.requiresPreparation) {
		MTLStages mtlVertexBefore = mtl4GpuToMtlStage(command->renderBarrier.vertex.stages);
		MTLStages mtlFragmentBefore = mtl4GpuToMtlStage(command->renderBarrier.fragment.stages);
		MTL4VisibilityOptions mtlVertexVisibility = mtl4GpuToMtlStage(command->renderBarrier.vertex.hazards);
		MTL4VisibilityOptions mtlFragmentVisibility = mtl4GpuToMtlStage(command->renderBarrier.fragment.hazards);
	
		if (context->computeUsedStages & mtlVertexBefore || context->computeUsedStages & mtlFragmentBefore) {
			mtl4FlushComputeEncoder(context);
		}
	
		if (mtlVertexBefore != 0) {
			[context->renderEncoder
				barrierAfterQueueStages:mtlVertexBefore
				beforeStages:MTLStageVertex
				visibilityOptions:mtlVertexVisibility];
		}
		if (mtlFragmentBefore != 0) {
			[context->renderEncoder
				barrierAfterQueueStages:mtlFragmentBefore
				beforeStages:MTLStageFragment
				visibilityOptions:mtlFragmentVisibility];
		}
	} else {
		mtl4FlushComputeEncoder(context);

		MTLStages mtlVertexBefore = MTLStageBlit;
		if (command->renderPass.containsMultiDraw) {
			mtlVertexBefore |= MTLStageDispatch;
		}

		MTLStages mtlFragmentBefore = mtl4GpuToMtlStage(command->renderBarrier.fragment.stages) & ~(MTLStageBlit | MTLStageDispatch);
		MTL4VisibilityOptions mtlVertexVisibility = mtl4GpuHazardsToMtlVisibilityOptions(command->renderBarrier.vertex.hazards);
		MTL4VisibilityOptions mtlFragmentVisibility = mtl4GpuHazardsToMtlVisibilityOptions(command->renderBarrier.fragment.hazards);

		if (mtlFragmentBefore == 0) {
			// NOTE: If the fragment barrier is skipped, then merge the visibility.
			mtlVertexVisibility |= mtlFragmentVisibility;
		}

		[context->renderEncoder
			barrierAfterQueueStages:mtlVertexBefore
			beforeStages:MTLStageVertex
			visibilityOptions:mtlVertexVisibility];

		if (mtlFragmentBefore != 0) {
			[context->renderEncoder
				barrierAfterQueueStages:mtlFragmentBefore
				beforeStages:MTLStageFragment
				visibilityOptions:mtlFragmentVisibility];
		}
	}
}

void mtl4EmitRenderpassBarriersForIndirectPrep(Mtl4CommandEmissionContext* context, Mtl4Command* command) {
	assert(command->type == MTL4_CMD_RENDERPASS);

	MTLStages mtlVertexBefore = mtl4GpuToMtlStage(command->renderBarrier.vertex.stages);
	MTL4VisibilityOptions mtlVertexVisibility = mtl4GpuToMtlStage(command->renderBarrier.vertex.hazards);

	if (context->computeUsedStages & mtlVertexBefore) {
		mtl4FlushComputeEncoder(context);
	}

	if (mtlVertexBefore != 0) {
		mtl4EnsureValidComputeEncoder(context);
		[context->renderEncoder
			barrierAfterQueueStages:mtlVertexBefore
			beforeStages:MTLStageVertex
			visibilityOptions:mtlVertexVisibility];
	}
}

void mtl4EmitBlitBarrier(Mtl4CommandEmissionContext* context, GpuStageFlags before, GpuHazardFlags hazards) {
	mtl4EmitBarrierForComputeStage(context, before, MTLStageBlit, hazards);
}

void mtl4EmitDispatchBarrier(Mtl4CommandEmissionContext* context, GpuStageFlags before, GpuHazardFlags hazards) {
	mtl4EmitBarrierForComputeStage(context, before, MTLStageDispatch, hazards);
}

void mtl4EmitCopyBufferToBuffer(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_COPY_BUFFER_TO_BUFFER);

	Mtl4CommandCopyBufferToBuffer* copy = &command->copyBufferToBuffer;

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

void mtl4EmitCopyBufferToTexture(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_COPY_BUFFER_TO_TEXTURE);

	Mtl4CommandCopyBufferToTexture* copy = &command->copyBufferToTexture;

	Mtl4AllocationMetadata* sourceMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(copy->source, true);
	if (sourceMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4TextureMetadata* textureMetadata = mtl4AcquireTextureMetadataFrom(copy->destinationTexture);
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

	size_t sourceOffset = mtl4GpuPtrOffsetFromBase(sourceMetadata, copy->source);

	// TODO: Support mipmaps.
	mtl4EnsureValidComputeEncoder(context);
	[context->computeEncoder copyFromBuffer:sourceMetadata->buffer
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

void mtl4EmitCopyTextureToBuffer(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_COPY_TEXTURE_TO_BUFFER);

	Mtl4CommandCopyTextureToBuffer* copy = &command->copyTextureToBuffer;
	
	Mtl4AllocationMetadata* destinationMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(copy->destination, true);
	if (destinationMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4TextureMetadata* textureMetadata = mtl4AcquireTextureMetadataFrom(copy->sourceTexture);
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

	size_t destinationOffset = mtl4GpuPtrOffsetFromBase(destinationMetadata, copy->destination);

	// TODO: Support mipmaps.
	mtl4EnsureValidComputeEncoder(context);
	[context->computeEncoder copyFromTexture:textureMetadata->texture
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

void mtl4EmitDispatch(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_DISPATCH);

	Mtl4CommandDispatch* dispatch = &command->dispatch;

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

void mtl4EmitDispatchIndirect(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_DISPATCH_INDIRECT);

	Mtl4CommandDispatchIndirect* dispatch = &command->dispatchIndirect;

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

void mtl4EmitSignal(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_SIGNAL);

	GpuResult localResult;

	Mtl4CommandSignal* signal = &command->signal;

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

	mtl4EmitBlitBarrier(context, command->barrier.stages, command->barrier.hazards);
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

void mtl4EmitWait(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_WAIT);

	GpuResult localResult;

	Mtl4CommandWait* wait = &command->wait;

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

void mtl4EmitDrawIndirectPrep(Mtl4CommandEmissionContext* context, Mtl4RenderCommand* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_DRAW_INDIRECT);

	Mtl4CommandDrawIndirect* draw = &command->drawIndirect;

	Mtl4AllocationMetadata* userArgsMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(draw->indirectArgs, true);
	if (userArgsMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	size_t userArgsOffsetFromBase = mtl4GpuPtrOffsetFromBase(userArgsMetadata, draw->indirectArgs);

	size_t argsOffset = mtl4BumpAllocIn(context, sizeof(MTLDrawIndexedPrimitivesIndirectArguments));
	
	// NOTE: Equivalent to:
	//	mtlIndirectArgs.indexCount = gpuIndirectArgs.indexCount
	//	mtlIndirectArgs.instanceCount = gpuIndirectArgs.instanceCount
	//	mtlIndirectArgs.indexStart = 0
	//	mtlIndirectArgs.baseVertex = 0
	//	mtlIndirectArgs.baseInstance = 0
	mtl4EnsureValidComputeEncoder(context);
	[context->computeEncoder
		copyFromBuffer:userArgsMetadata->buffer
		sourceOffset:userArgsOffsetFromBase
		toBuffer:context->bumpBuffer
		destinationOffset:argsOffset
		size:sizeof(GpuIndirectDrawArgs)];
	[context->computeEncoder
		copyFromBuffer:gMtl4Context.zeroBuffer
		sourceOffset:0
		toBuffer:context->bumpBuffer
		destinationOffset:argsOffset + sizeof(GpuIndirectDrawArgs)
	 	size:sizeof(MTLDrawIndexedPrimitivesIndirectArguments) - sizeof(GpuIndirectDrawArgs)];

	draw->preparedIndirectArgsOffset = argsOffset;
}

void mtl4EmitMultiDrawIndirectPrep(Mtl4CommandEmissionContext* context, Mtl4RenderCommand* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_MULTIDRAW_INDIRECT);

	Mtl4CommandMultiDrawIndirect* draw = &command->multiDrawIndirect;


	Mtl4PipelineMetadata* acquireIcbRangePipelineMetadata = mtl4AcquirePipelineMetadataFrom(gMtl4Context.acquireIcbRange);
	assert(acquireIcbRangePipelineMetadata != nullptr && "The builtin pipeline could not be found.");
	defer (mtl4ReleasePipelineMetadata());

	Mtl4PipelineMetadata* prepareIcbsPipelineMetadata = mtl4AcquirePipelineMetadataFrom(gMtl4Context.prepareMultidrawIcbs);
	assert(prepareIcbsPipelineMetadata != nullptr && "The builtin pipeline could not be found.");
	defer (mtl4ReleasePipelineMetadata());

	Mtl4PipelineMetadata* drawPipelineMetadata = mtl4AcquirePipelineMetadataFrom(command->pipeline);
	if (drawPipelineMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_PIPELINE_FOUND);
		return;
	}
	defer (mtl4ReleasePipelineMetadata());


	size_t acquireIcbRangeArgsOffset = mtl4BumpAllocIn(context, sizeof(Mtl4AcquireIcbRangeArgs));
	Mtl4AcquireIcbRangeArgs* acquireIcbRangeArgs = (Mtl4AcquireIcbRangeArgs*)((uintptr_t)[context->bumpBuffer contents] + acquireIcbRangeArgsOffset);

	size_t prepareIcbsArgsOffset = mtl4BumpAllocIn(context, sizeof(Mtl4PrepareMultidrawIndirectIcbsArgs));
	Mtl4PrepareMultidrawIndirectIcbsArgs* prepareIcbsArgs = (Mtl4PrepareMultidrawIndirectIcbsArgs*)((uintptr_t)[context->bumpBuffer contents] + prepareIcbsArgsOffset);

	size_t rangeOffset = mtl4BumpAllocIn(context, sizeof(MTLIndirectCommandBufferExecutionRange));


	acquireIcbRangeArgs->outRange = [context->bumpBuffer gpuAddress] + rangeOffset;
	acquireIcbRangeArgs->firstFreeIdx = [context->firstFreeIcbIndex gpuAddress];
	acquireIcbRangeArgs->requiredLength = (uintptr_t)draw->indirectDrawCount;
	[context->computeArgumentTable setAddress:[context->bumpBuffer gpuAddress] + acquireIcbRangeArgsOffset atIndex:0];

	mtl4EnsureValidComputeEncoder(context);
	[context->computeEncoder setComputePipelineState:acquireIcbRangePipelineMetadata->compute.pso];
	[context->computeEncoder setArgumentTable:context->computeArgumentTable];
	[context->computeEncoder dispatchThreads:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];


	prepareIcbsArgs->commandBuffer = [context->icbBuffer gpuResourceID];
	prepareIcbsArgs->icbRange = [context->bumpBuffer gpuAddress] + rangeOffset;
	prepareIcbsArgs->primitive = gMtl4GpuTopologyToMtlPrimitive[drawPipelineMetadata->graphics.desc.topology];
	prepareIcbsArgs->textureHeap = (uintptr_t)command->textureHeapPtr;
	prepareIcbsArgs->vertexData = (uintptr_t)draw->vertexData;
	prepareIcbsArgs->vertexStride = draw->vertexStride;
	prepareIcbsArgs->fragmentData = (uintptr_t)draw->pixelData;
	prepareIcbsArgs->fragmentStride = draw->pixelStride;
	prepareIcbsArgs->args = (uintptr_t)draw->indirectArgs;
	prepareIcbsArgs->argCount = (uintptr_t)draw->indirectDrawCount;
	[context->computeArgumentTable setAddress:[context->bumpBuffer gpuAddress] + prepareIcbsArgsOffset atIndex:0];

	mtl4FlushComputeEncoder(context);
	mtl4EnsureValidComputeEncoder(context);
	[context->computeEncoder barrierAfterQueueStages:MTLStageDispatch beforeStages:MTLStageDispatch visibilityOptions:MTL4VisibilityOptionDevice];
	[context->computeEncoder setComputePipelineState:prepareIcbsPipelineMetadata->compute.pso];
	[context->computeEncoder setArgumentTable:context->computeArgumentTable];
	[context->computeEncoder dispatchThreads:MTLSizeMake(MTL4_MAX_MULTIDRAW_ARG_COUNT, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];

	draw->preparedIcbRangeOffset = rangeOffset;
}

void mtl4EmitRenderpassPrep(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_RENDERPASS);

	mtl4EmitRenderpassBarriersForIndirectPrep(context, command);

	CmnChainIterator<Mtl4RenderCommand> iter;
	cmnCreateChainIterator(&command->renderPass.commands, &iter);

	GpuResult localResult;
	GpuResult lastError = GPU_SUCCESS;

	Mtl4RenderCommand* renderCommand;
	while (cmnIterate(&iter, &renderCommand)) {
		switch (renderCommand->type) {
			case MTL4_CMD_DRAW_INDIRECT: {
				mtl4EmitDrawIndirectPrep(context, renderCommand, &localResult);
				if (localResult != GPU_SUCCESS) {
					lastError = localResult;
				}

				break;
			}
			case MTL4_CMD_MULTIDRAW_INDIRECT: {
				mtl4EmitMultiDrawIndirectPrep(context, renderCommand, &localResult);
				if (localResult != GPU_SUCCESS) {
					lastError = localResult;
				}

				break;
			}
			default: break;
		}
	}

	CMN_SET_RESULT(result, lastError);
}

void mtl4EmitBeginRenderpass(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_RENDERPASS);
	
	Mtl4CommandRenderPass* renderPass = &command->renderPass;
	const GpuRenderPassDesc* desc = renderPass->desc;

	MTL4RenderPassDescriptor* renderPassDesc = [[MTL4RenderPassDescriptor new] autorelease];
	for (size_t i = 0; i < desc->colorTargetCount; i++) {
		const GpuRenderTarget* target = &desc->colorTargets[i];

		Mtl4Texture targetTextureHandle = mtl4GpuTextureToHadle(target->texture);
		Mtl4TextureMetadata* targetTexture = mtl4AcquireTextureMetadataFrom(targetTextureHandle);
		if (targetTexture == nullptr) {
			CMN_SET_RESULT(result, GPU_NO_SUCH_TEXTURE_FOUND);
			return;
		}
		defer (mtl4ReleaseTextureMetadata());

		MTLRenderPassColorAttachmentDescriptor* colorAttachment = [[MTLRenderPassColorAttachmentDescriptor new] autorelease];
		colorAttachment.texture = targetTexture->texture;
		colorAttachment.loadAction = gMtl4GpuTargetOpToMtlLoadAction[target->loadOp];
		colorAttachment.storeAction = gMtl4GpuTargetOpToMtlStoreAction[target->storeOp];
		colorAttachment.clearColor = MTLClearColorMake(
			target->clearColor[0],
			target->clearColor[1],
			target->clearColor[2],
			target->clearColor[3]
		);

		renderPassDesc.colorAttachments[i] = colorAttachment;

	}

	if (desc->depthTarget != nullptr) {
		Mtl4Texture depthTargetHandle = mtl4GpuTextureToHadle(desc->depthTarget->texture);
		Mtl4TextureMetadata* depthTarget = mtl4AcquireTextureMetadataFrom(depthTargetHandle);
		if (depthTarget == nullptr) {
			CMN_SET_RESULT(result, GPU_NO_SUCH_TEXTURE_FOUND);
			return;
		}
		defer (mtl4ReleaseTextureMetadata());

		MTLRenderPassDepthAttachmentDescriptor* depthAttachment = [[MTLRenderPassDepthAttachmentDescriptor new] autorelease];
		depthAttachment.texture = depthTarget->texture;
		depthAttachment.clearDepth = desc->depthTarget->depthClearValue;
		depthAttachment.loadAction = gMtl4GpuTargetOpToMtlLoadAction[desc->depthTarget->loadOp];
		depthAttachment.storeAction = gMtl4GpuTargetOpToMtlStoreAction[desc->depthTarget->storeOp];

		renderPassDesc.depthAttachment = depthAttachment;
	}

	if (desc->stencilTarget != nullptr) {
		Mtl4Texture stencilTargetHandle = mtl4GpuTextureToHadle(desc->stencilTarget->texture);
		Mtl4TextureMetadata* stencilTarget = mtl4AcquireTextureMetadataFrom(stencilTargetHandle);
		if (stencilTarget == nullptr) {
			CMN_SET_RESULT(result, GPU_NO_SUCH_TEXTURE_FOUND);
			return;
		}
		defer (mtl4ReleaseTextureMetadata());

		MTLRenderPassStencilAttachmentDescriptor* stencilAttachment = [[MTLRenderPassStencilAttachmentDescriptor new] autorelease];
		stencilAttachment.texture = stencilTarget->texture;
		stencilAttachment.clearStencil = desc->stencilTarget->stencilClearValue;
		stencilAttachment.loadAction = gMtl4GpuTargetOpToMtlLoadAction[desc->stencilTarget->loadOp];
		stencilAttachment.storeAction = gMtl4GpuTargetOpToMtlStoreAction[desc->stencilTarget->storeOp];

		renderPassDesc.stencilAttachment = stencilAttachment;
	}

	mtl4EnsureValidCommandBuffer(context);
	mtl4FlushComputeEncoder(context);
	context->renderEncoder = [context->commandBuffer renderCommandEncoderWithDescriptor:renderPassDesc];

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

MTLPrimitiveType mtl4EmitDrawSetup(Mtl4CommandEmissionContext* context, Mtl4RenderCommand* command, GpuResult* result) {
	Mtl4PipelineMetadata* pipeline = mtl4AcquirePipelineMetadataFrom(command->pipeline);
	if (pipeline == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_PIPELINE_FOUND);
		return MTLPrimitiveTypeTriangle;
	}
	defer (mtl4ReleasePipelineMetadata());
	[context->renderEncoder setRenderPipelineState:pipeline->graphics.pso];

	if (!cmnIsZero(command->depthStencil)) {
		Mtl4DepthStencilStateMetadata* depthStencil = mtl4AcquireDepthStencilStateMetadataFrom(command->depthStencil);
		if (depthStencil == nullptr) {
			CMN_SET_RESULT(result, GPU_NO_SUCH_DEPTH_STENCIL_STATE_FOUND);
			return MTLPrimitiveTypeTriangle;
		}
		defer (mtl4ReleaseDepthStencilStateMetadata());

		[context->renderEncoder setDepthStencilState:depthStencil->depthStencilState];
	}

	[context->fragmentArgumentTable setAddress:(uintptr_t)command->textureHeapPtr atIndex:1];

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return gMtl4GpuTopologyToMtlPrimitive[pipeline->graphics.desc.topology];
}

void mtl4EmitDraw(Mtl4CommandEmissionContext* context, Mtl4RenderCommand* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_DRAW);

	CMN_SET_RESULT(result, GPU_SUCCESS);

	Mtl4CommandDraw* draw = &command->draw;

	MTLPrimitiveType primitive = mtl4EmitDrawSetup(context, command, result);

	[context->vertexArgumentTable setAddress:(uintptr_t)draw->vertexData atIndex:0];
	[context->fragmentArgumentTable setAddress:(uintptr_t)draw->pixelData atIndex:0];

	[context->renderEncoder setArgumentTable:context->vertexArgumentTable atStages:MTLStageVertex];
	[context->renderEncoder setArgumentTable:context->fragmentArgumentTable atStages:MTLStageFragment];
	[context->renderEncoder
		drawIndexedPrimitives:primitive
		indexCount:draw->indexCount
		indexType:MTLIndexTypeUInt32
		indexBuffer:(uintptr_t)draw->indices
		indexBufferLength:sizeof(uint32_t) * draw->indexCount
		instanceCount:draw->instanceCount];
}

void mtl4EmitDrawIndirect(Mtl4CommandEmissionContext* context, Mtl4RenderCommand* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_DRAW_INDIRECT);

	Mtl4CommandDrawIndirect* draw = &command->drawIndirect;

	Mtl4AllocationMetadata* indicesMetadata = mtl4AcquireAllocationMetadataFromGpuPtr(draw->indices, true);
	if (indicesMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
	}
	defer (mtl4ReleaseAllocationMetadata());

	size_t indicesLength = indicesMetadata->size - mtl4GpuPtrOffsetFromBase(indicesMetadata, draw->indices);

	MTLPrimitiveType primitive = mtl4EmitDrawSetup(context, command, result);

	[context->vertexArgumentTable setAddress:(uintptr_t)draw->vertexData atIndex:0];
	[context->fragmentArgumentTable setAddress:(uintptr_t)draw->pixelData atIndex:0];

	[context->renderEncoder setArgumentTable:context->vertexArgumentTable atStages:MTLStageVertex];
	[context->renderEncoder setArgumentTable:context->fragmentArgumentTable atStages:MTLStageFragment];
	[context->renderEncoder
		drawIndexedPrimitives:primitive
		indexType:MTLIndexTypeUInt32
		indexBuffer:(uintptr_t)draw->indices
		indexBufferLength:indicesLength
		indirectBuffer:[context->bumpBuffer gpuAddress] + draw->preparedIndirectArgsOffset];

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4EmitMultiDrawIndirect(Mtl4CommandEmissionContext* context, Mtl4RenderCommand* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_MULTIDRAW_INDIRECT);

	Mtl4CommandMultiDrawIndirect* draw = &command->multiDrawIndirect;

	mtl4EmitDrawSetup(context, command, result);
	[context->renderEncoder
		executeCommandsInBuffer:context->icbBuffer
		indirectBuffer:[context->bumpBuffer gpuAddress] + draw->preparedIcbRangeOffset];

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4EmitRenderpass(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result) {
	assert(command->type == MTL4_CMD_RENDERPASS);

	if (command->renderPass.requiresPreparation) {
		mtl4EmitRenderpassPrep(context, command, result);
	}

	mtl4EmitBeginRenderpass(context, command, result);
	mtl4EmitRenderpassBarriers(context, command);

	CmnChainIterator<Mtl4RenderCommand> iter;
	cmnCreateChainIterator((CmnChain<Mtl4RenderCommand>*)&command->renderPass.commands, &iter);

	Mtl4RenderCommand* renderCommand;
	while (cmnIterate(&iter, &renderCommand)) {
		switch (renderCommand->type) {
			case MTL4_CMD_DRAW: {
				mtl4EmitDraw(context, renderCommand, result);
				break;
			}
			case MTL4_CMD_DRAW_INDIRECT: {
				mtl4EmitDrawIndirect(context, renderCommand, result);
				break;
			}
			case MTL4_CMD_MULTIDRAW_INDIRECT: {
				mtl4EmitMultiDrawIndirect(context, renderCommand, result);
				break;
			}
		}
	}

	[context->renderEncoder endEncoding];
	context->renderEncoder = nil;

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4EmitCommand(Mtl4CommandEmissionContext* context, Mtl4Command* command, GpuResult* result) {
	switch (command->type) {
		case MTL4_CMD_COPY_BUFFER_TO_BUFFER: {
			mtl4EmitBlitBarrier(context, command->barrier.stages, command->barrier.hazards);
			mtl4EmitCopyBufferToBuffer(context, command, result);

			break;
		}
		case MTL4_CMD_COPY_BUFFER_TO_TEXTURE: {
			mtl4EmitBlitBarrier(context, command->barrier.stages, command->barrier.hazards);
			mtl4EmitCopyBufferToTexture(context, command, result);

			break;
		}
		case MTL4_CMD_COPY_TEXTURE_TO_BUFFER: {
			mtl4EmitBlitBarrier(context, command->barrier.stages, command->barrier.hazards);
			mtl4EmitCopyTextureToBuffer(context, command, result);

			break;
		}
		case MTL4_CMD_DISPATCH: {
			mtl4EmitDispatchBarrier(context, command->barrier.stages, command->barrier.hazards);
			mtl4EmitDispatch(context, command, result);

			break;
		}
		case MTL4_CMD_DISPATCH_INDIRECT: {
			mtl4EmitDispatchBarrier(context, command->barrier.stages, command->barrier.hazards);
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
		case MTL4_CMD_RENDERPASS: {
			mtl4EmitRenderpass(context, command, result);
			break;
		}
	}
}

void mtl4EmitSemaphoreSignal(
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

MTLStages mtl4GpuToMtlStage(GpuStageFlags stage) {
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
	if (stage & GPU_STAGE_RASTER_DEPTHSTENCIL_OUT) {
		stages |= MTLStageFragment;
	}

	return stages;
}

MTL4VisibilityOptions mtl4GpuHazardsToMtlVisibilityOptions(GpuHazardFlags hazards) {
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

