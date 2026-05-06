#include "fences.h"

#include <lib/common/heap_allocator.h>
#include <lib/metal4/command_buffers.h>
#include <lib/metal4/context.h>
#include <lib/metal4/allocation.h>

Mtl4EventStorage gMtl4EventStorage;

void mtl4InitEventStorage(GpuResult* result) {
	CmnResult localResult;

	gMtl4EventStorage = {};

	gMtl4EventStorage.page = cmnCreatePage(1024 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	gMtl4EventStorage.arena = cmnPageToArena(gMtl4EventStorage.page);

	cmnCreatePointerMap(&gMtl4EventStorage.lookup, 1024, {}, cmnHeapAllocator(), &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	// gMtl4EventStorage.signaledValuesUploadBuffer = [gMtl4Context.device newBufferWithLength:16384 options:MTLResourceStorageModeShared | MTLResourceCPUCacheModeDefaultCache];
	// gMtl4EventStorage.signaledValuesUploadBuffer = [gMtl4Context.device newBufferWithLength:16384 options:MTLResourceStorageModeShared | MTLResourceHazardTrackingModeTracked];
	gMtl4EventStorage.signaledValuesUploadBuffer = [gMtl4Context.device newBufferWithLength:1024*1024 options:MTLResourceStorageModeShared | MTLResourceCPUCacheModeDefaultCache];
	gMtl4EventStorage.uploadBufferSize = 1024 * 1024;
	gMtl4EventStorage.uploadBufferUsed = 0;

	MTLResidencySetDescriptor* residencySetDescriptor = [MTLResidencySetDescriptor new];
	defer ([residencySetDescriptor release]);
	residencySetDescriptor.initialCapacity = 1;
	residencySetDescriptor.label = @"Signaled values upload residency set";

	gMtl4EventStorage.uploadBufferResidencySet = [gMtl4Context.device newResidencySetWithDescriptor:residencySetDescriptor error:nil];
	[gMtl4EventStorage.uploadBufferResidencySet addAllocation:gMtl4EventStorage.signaledValuesUploadBuffer];
	[gMtl4EventStorage.uploadBufferResidencySet commit];

	if (gMtl4EventStorage.signaledValuesUploadBuffer == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4FiniEventStorage() {
	cmnDestroyPage(gMtl4EventStorage.page);
	[gMtl4EventStorage.signaledValuesUploadBuffer release];

	gMtl4EventStorage = {};
}

id<MTLEvent> mtl4AcquireEventOf(void* gpuPtr) {
	bool wasHandleValid;
	id<MTLEvent> event = *cmnStorageSyncAcquireResource(&gMtl4EventStorage.lookup, &gMtl4EventStorage.sync, (uintptr_t)gpuPtr, &wasHandleValid);
	if (!wasHandleValid) {
		return nil;
	}

	return event;
}


id<MTLEvent> mtl4AcquireOrCreateEventFor(void* gpuPtr, GpuResult* result) {
	CmnResult localResult;

	id<MTLEvent> event = mtl4AcquireEventOf(gpuPtr);
	if (event != nil) {
		CMN_SET_RESULT(result, GPU_SUCCESS);
		return event;
	}

	event = [gMtl4Context.device newEvent];
	if (event == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return nil;
	}

	CmnScopedStorageSyncLockWrite guard(&gMtl4EventStorage.sync);

	bool raceOccurred;
	id<MTLEvent> raceCollision = cmnGet(&gMtl4EventStorage.lookup, (uintptr_t)gpuPtr, &raceOccurred);
	if (raceOccurred) {
		// Another thread got here before us.
		[event release];

		cmnStorageSyncMarkAsUsingResources(&gMtl4EventStorage.sync);
		CMN_SET_RESULT(result, GPU_SUCCESS);
		return raceCollision;
	} else {

		cmnInsert(&gMtl4EventStorage.lookup, (uintptr_t)gpuPtr, event, &localResult);
		if (localResult != CMN_SUCCESS) {
			[event release];

			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return nil;
		}

		cmnStorageSyncMarkAsUsingResources(&gMtl4EventStorage.sync);
		CMN_SET_RESULT(result, GPU_SUCCESS);
		return event;
	}
}

void mtl4ReleaseEvent(void) {
	cmnStorageSyncReleaseResource(&gMtl4EventStorage.sync);
}

size_t mtl4UploadFenceValue(uint64_t value) {
	uintptr_t values = (uintptr_t)[gMtl4EventStorage.signaledValuesUploadBuffer contents];

	size_t valueOffset;
	for (;;) {
		valueOffset = cmnAtomicLoad(&gMtl4EventStorage.uploadBufferUsed);
		if (valueOffset >= gMtl4EventStorage.uploadBufferSize) {
			valueOffset = 0;
		}

		if (cmnAtomicCompareExchangeStrong<uint64_t>(
			&gMtl4EventStorage.uploadBufferUsed,
			valueOffset,
			valueOffset + sizeof(uint64_t)
		)) {
			break;
		}
	}

	uint64_t* valuePtr = (uint64_t*)(values + valueOffset);
	*valuePtr = value;

	uint64_t* fs = (uint64_t*)values;
	printf("First 256 values of the upload buffer (offset: %llu, returning: %llu): ", gMtl4EventStorage.uploadBufferUsed, (uint64_t)valueOffset);
	for (size_t i = 0; i < 256; i++) {
		printf("%llu ", fs[i]);
	}
	printf("\n");

	return valueOffset;
}

void mtl4SignalEvent(
	Mtl4CommandBufferMetadata* commandBuffer,
	GpuStage after,
	void* gpuPtr,
	uint64_t value,
	GpuResult* result
) {
	(void)after;

	GpuResult localResult;

	id<MTLEvent> event = mtl4AcquireOrCreateEventFor(gpuPtr, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}
	defer (mtl4ReleaseEvent());

	Mtl4AllocationMetadata* allocation = mtl4AcquireAllocationMetadataFromGpuPtr(gpuPtr);
	if (allocation == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	mtl4EnsureBackingBufferIsAllocated(allocation, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}

	uintptr_t gpuPtrOffsetFromBase = mtl4GpuAddressOffsetFromBase(gpuPtr);

	size_t fenceUploadValueOffset = mtl4UploadFenceValue(value);

	if ([commandBuffer->computeEncoder stages] != 0) {
		[commandBuffer->computeEncoder endEncoding];
		commandBuffer->computeEncoder = [commandBuffer->commandBuffer computeCommandEncoder];
	}

	// TODO: Figure out the big buffer
	// id<MTLBuffer> uploadBuffer = [gMtl4Context.device newBufferWithBytes:&value length:sizeof(uint64_t) options:MTLResourceStorageModePrivate];
	// *(uint64_t*)[uploadBuffer contents] = value;
	// defer ([uploadBuffer release]);

	*(uint64_t*)[gMtl4EventStorage.signaledValuesUploadBuffer contents] = value;

	[commandBuffer->computeEncoder barrierAfterQueueStages:MTLStageAll beforeStages:MTLStageBlit visibilityOptions:MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias];
	[commandBuffer->computeEncoder
		copyFromBuffer:gMtl4EventStorage.signaledValuesUploadBuffer
		sourceOffset:fenceUploadValueOffset
		// copyFromBuffer:uploadBuffer
		// sourceOffset:0
		toBuffer:allocation->buffer
		destinationOffset:gpuPtrOffsetFromBase
		size:sizeof(uint64_t)];
	[commandBuffer->computeEncoder endEncoding];
	[commandBuffer->commandBuffer endCommandBuffer];

	[commandBuffer->queue commit:&commandBuffer->commandBuffer count:1];
	[commandBuffer->queue signalEvent:event value:value];
	// [commandBuffer->commandBuffer release];

	commandBuffer->commandBuffer = [gMtl4Context.device newCommandBuffer];
	[commandBuffer->commandBuffer beginCommandBufferWithAllocator:commandBuffer->commandAllocator];
	commandBuffer->computeEncoder = [commandBuffer->commandBuffer computeCommandEncoder];
}


void mtl4WaitEvent(
	Mtl4CommandBufferMetadata* commandBuffer,
	GpuStage before,
	void* gpuPtr,
	uint64_t value,
	GpuResult* result
) {
	(void)before;

	GpuResult localResult;

	id<MTLEvent> event = mtl4AcquireOrCreateEventFor(gpuPtr, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}
	defer (mtl4ReleaseEvent());

	if (commandBuffer->computeEncoder != nil) {
		[commandBuffer->computeEncoder endEncoding];
	}
	// if (commandBuffer->renderEncoder != nil) {
	// 	[commandBuffer->renderEncoder endEncoding];
	// }
	[commandBuffer->commandBuffer endCommandBuffer];

	[commandBuffer->queue waitForEvent:event value:value];
	[commandBuffer->queue commit:&commandBuffer->commandBuffer count:1];
	// [commandBuffer->commandBuffer release];

	commandBuffer->commandBuffer = [gMtl4Context.device newCommandBuffer];
	[commandBuffer->commandBuffer beginCommandBufferWithAllocator:commandBuffer->commandAllocator];
	commandBuffer->computeEncoder = [commandBuffer->commandBuffer computeCommandEncoder];

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

// Mtl4FenceMetadata* mtl4AcquireFenceMetadataFrom(void* gpuPtr, uint64_t value) {
// 	bool didFindFence;
// 	Mtl4FenceHandle handle = mtl4FenceHandleFrom(gpuPtr, value, &didFindFence);
// 	if (!didFindFence) {
// 		return nullptr;
// 	}

// 	Mtl4FenceMetadata* metadata = cmnStorageSyncAcquireResource(&gMtl4EventStorage.fences, &gMtl4EventStorage.sync, handle, &didFindFence);
// 	if (!didFindFence) {
// 		return nullptr;
// 	}

// 	return metadata;
// }

// Mtl4FenceMetadata* mtl4AcquireOrCreateFenceMetadataFor(void* gpuPtr, uint64_t value, GpuResult* result) {
// 	CmnResult localResult;

// 	Mtl4FenceMetadata* metadata = mtl4AcquireFenceMetadataFrom(gpuPtr, value);
// 	if (metadata != nil) {
// 		CMN_SET_RESULT(result, GPU_SUCCESS);
// 		return metadata;
// 	}

// 	Mtl4FenceMetadata newMetadata;

// 	// newMetadata.gpuPtrUpdatedFence = [gMtl4Context.device newFence];
// 	// if (newMetadata.gpuPtrUpdatedFence == nil) {
// 	// 	CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
// 	// 	return metadata;
// 	// }

// 	newMetadata.computeWriteGpuPtrFence = [gMtl4Context.device newFence];
// 	if (newMetadata.computeWriteGpuPtrFence == nil) {
// 		// [newMetadata.gpuPtrUpdatedFence release];

// 		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
// 		return metadata;
// 	}

// 	// newMetadata.renderWriteGpuPtrFence = [gMtl4Context.device newFence];
// 	// if (newMetadata.renderWriteGpuPtrFence == nil) {
// 	// 	[newMetadata.computeWriteGpuPtrFence release];
// 	// 	[newMetadata.gpuPtrUpdatedFence release];

// 	// 	CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
// 	// 	return metadata;
// 	// }

// 	CmnScopedStorageSyncLockWrite guard(&gMtl4EventStorage.sync);

// 	Mtl4FenceId fenceId = { gpuPtr, value };

// 	bool containsFence;
// 	Mtl4FenceHandle fenceHandle = cmnGet(&gMtl4EventStorage.lookup, fenceId, &containsFence);
// 	if (containsFence) {
// 		// NOTE: Some other thread beated us on time.

// 		metadata = &cmnGet(&gMtl4EventStorage.fences, fenceHandle, &containsFence);
// 		assert(containsFence && "Something is horrendously wrong here.");

// 		cmnStorageSyncMarkAsUsingResources(&gMtl4EventStorage.sync);

// 		// [newMetadata.gpuPtrUpdatedFence release];
// 		[newMetadata.computeWriteGpuPtrFence release];
// 		// [newMetadata.renderWriteGpuPtrFence release];

// 		CMN_SET_RESULT(result, GPU_SUCCESS);
// 		return metadata;
// 	} else {
// 		fenceHandle = cmnInsert(&gMtl4EventStorage.fences, newMetadata, &localResult);
// 		if (localResult != CMN_SUCCESS) {
// 			// [newMetadata.gpuPtrUpdatedFence release];
// 			[newMetadata.computeWriteGpuPtrFence release];
// 			// [newMetadata.renderWriteGpuPtrFence release];

// 			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
// 			return metadata;
// 		}

// 		cmnInsert(&gMtl4EventStorage.lookup, fenceId, fenceHandle, &localResult);
// 		if (localResult != CMN_SUCCESS) {
// 			cmnRemove(&gMtl4EventStorage.fences, fenceHandle);

// 			// [newMetadata.gpuPtrUpdatedFence release];
// 			[newMetadata.computeWriteGpuPtrFence release];
// 			// [newMetadata.renderWriteGpuPtrFence release];

// 			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
// 			return metadata;
// 		}

// 		metadata = &cmnGet(&gMtl4EventStorage.fences, fenceHandle, &containsFence);
// 		assert(containsFence && "Something is horrendously wrong here.");

// 		cmnStorageSyncMarkAsUsingResources(&gMtl4EventStorage.sync);

// 		CMN_SET_RESULT(result, GPU_SUCCESS)
// 		return metadata;
// 	}
// }

// void mtl4SignalFence(
// 	Mtl4CommandBufferMetadata* commandBuffer,
// 	GpuStage before,
// 	void* gpuPtr,
// 	uint64_t value,
// 	GpuResult* result
// ) {
// 	GpuResult localResult;

// 	Mtl4FenceMetadata* metadata = mtl4AcquireOrCreateFenceMetadataFor(gpuPtr, value, &localResult);
// 	if (localResult != GPU_SUCCESS) {
// 		CMN_SET_RESULT(result, localResult);
// 		return;
// 	}
// 	defer (mtl4ReleaseFenceMetadata());

// 	Mtl4AllocationMetadata* allocation = mtl4AcquireAllocationMetadataFromGpuPtr(gpuPtr);
// 	if (allocation == nullptr) {
// 		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
// 		return;
// 	}
// 	defer (mtl4ReleaseAllocationMetadata());

// 	mtl4EnsureBackingBufferIsAllocated(allocation, &localResult);
// 	if (localResult != GPU_SUCCESS) {
// 		CMN_SET_RESULT(result, localResult);
// 		return;
// 	}

// 	uintptr_t gpuPtrOffsetFromBase = mtl4GpuAddressOffsetFromBase(gpuPtr);

// 	MTLStages mtlStages	= mtl4GpuToMtlStage(before);

// 	size_t fenceUploadValueOffset = mtl4UploadFenceValue(value);

// 	if ([commandBuffer->computeEncoder stages] != 0) {
// 		[commandBuffer->computeEncoder endEncoding];
// 		commandBuffer->computeEncoder = [commandBuffer->commandBuffer computeCommandEncoder];
// 	}

// 	[commandBuffer->computeEncoder barrierAfterQueueStages:mtlStages beforeStages:MTLStageBlit visibilityOptions:MTL4VisibilityOptionNone];
// 	[commandBuffer->computeEncoder
// 		copyFromBuffer:gMtl4EventStorage.fenceUploadBuffer
// 		sourceOffset:fenceUploadValueOffset
// 		toBuffer:allocation->buffer
// 		destinationOffset:gpuPtrOffsetFromBase
// 		size:sizeof(uint64_t)];
// 	[commandBuffer->computeEncoder updateFence:metadata->computeWriteGpuPtrFence afterEncoderStages:MTLStageBlit];
// 	[commandBuffer->computeEncoder endEncoding];

// 	commandBuffer->computeEncoder = [commandBuffer->commandBuffer computeCommandEncoder];
// 	[commandBuffer->computeEncoder waitForFence:metadata->computeWriteGpuPtrFence beforeEncoderStages:MTLStageBlit];
// 	// [commandBuffer->computeEncoder
// 	//  	barrierAfterQueueStages:MTLStageBlit
// 	//  	beforeStages:MTLStageBlit | MTLStageDispatch | MTLStageAccelerationStructure
// 	//  	visibilityOptions:MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias];
// }

// void mtl4WaitFence(
// 	Mtl4CommandBufferMetadata* commandBuffer,
// 	GpuStage after,
// 	void* gpuPtr,
// 	uint64_t value,
// 	GpuResult* result
// ) {
// 	GpuResult localResult;

// 	Mtl4FenceMetadata* metadata = mtl4AcquireOrCreateFenceMetadataFor(gpuPtr, value, &localResult);
// 	if (localResult != GPU_SUCCESS) {
// 		CMN_SET_RESULT(result, localResult);
// 		return;
// 	}
// 	defer (mtl4ReleaseFenceMetadata());

// 	MTLStages mtlComputeStages = mtl4GpuToMtlStage(after) & (MTLStageBlit | MTLStageDispatch);
// 	// MTLStages mtlRenderStages = mtl4GpuToMtlStage(after) & (MTLStageTile | MTLStageFragment | MTLStageVertex);

// 	if (mtl4IsStageCompute(after)) {
// 		if ([commandBuffer->computeEncoder stages] != 0) {
// 			[commandBuffer->computeEncoder endEncoding];
// 			commandBuffer->computeEncoder = [commandBuffer->commandBuffer computeCommandEncoder];
// 		}

// 		[commandBuffer->computeEncoder waitForFence:metadata->computeWriteGpuPtrFence beforeEncoderStages:mtlComputeStages];
// 	}
// 	// if (mtl4IsStageRender(after)) {
// 	// 	[commandBuffer->renderEncoder waitForFence:metadata->gpuPtrUpdatedFence beforeEncoderStages:mtlRenderStages];
// 	// }

// 	CMN_SET_RESULT(result, GPU_SUCCESS);
// }

