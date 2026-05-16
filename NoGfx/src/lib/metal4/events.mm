#include "events.h"

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

	gMtl4EventStorage.signaledValuesUploadBuffer = [
		gMtl4Context.device
		newBufferWithLength:1024*1024
		options:MTLResourceStorageModeShared | MTLResourceCPUCacheModeWriteCombined];
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

	return valueOffset;
}

void mtl4SignalEvent(
	Mtl4CommandBufferMetadata* commandBuffer,
	GpuStageFlags after,
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

	Mtl4AllocationMetadata* allocation = mtl4AcquireAllocationMetadataFromGpuPtr(gpuPtr, true);
	if (allocation == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	uintptr_t gpuPtrOffsetFromBase = mtl4GpuPtrOffsetFromBase(allocation, gpuPtr);

	size_t fenceUploadValueOffset = mtl4UploadFenceValue(value);

	// mtl4FlushCommandEncoderOf(commandBuffer);
	// mtl4EnsureValidComputeEndoderFor(commandBuffer);
	// [commandBuffer->computeEncoder barrierAfterQueueStages:MTLStageAll beforeStages:MTLStageBlit visibilityOptions:MTL4VisibilityOptionDevice | MTL4VisibilityOptionResourceAlias];
	// [commandBuffer->computeEncoder
	// 	copyFromBuffer:gMtl4EventStorage.signaledValuesUploadBuffer
	// 	sourceOffset:fenceUploadValueOffset
	// 	toBuffer:allocation->buffer
	// 	destinationOffset:gpuPtrOffsetFromBase
	// 	size:sizeof(uint64_t)];

	// mtl4FlushCommandBuffer(commandBuffer);
	// [commandBuffer->queue signalEvent:event value:value];
}


void mtl4WaitEvent(
	Mtl4CommandBufferMetadata* commandBuffer,
	GpuStageFlags before,
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

	// mtl4FlushCommandBuffer(commandBuffer);
	// [commandBuffer->queue waitForEvent:event value:value];

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

