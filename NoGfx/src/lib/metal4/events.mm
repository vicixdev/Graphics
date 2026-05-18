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

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4FiniEventStorage() {
	cmnDestroyPage(gMtl4EventStorage.page);

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

