#include "semaphores.h"

#include <lib/metal4/context.h>

Mtl4SemaphoreStorage gMtl4SemaphoreStorage;

void mtl4InitSemaphoreStorage(GpuResult* result) {
	CmnResult localResult;

	gMtl4SemaphoreStorage.page = cmnCreatePage(512 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	gMtl4SemaphoreStorage.arena = cmnPageToArena(gMtl4SemaphoreStorage.page);

	cmnCreateHandleMap(&gMtl4SemaphoreStorage.semaphores, cmnArenaAllocator(&gMtl4SemaphoreStorage.arena), {}, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4FiniSemaphoreStorage(void) {
	cmnDestroyPage(gMtl4SemaphoreStorage.page);
	gMtl4SemaphoreStorage = {};
}

GpuSemaphore mtl4CreateSemaphore(uint64_t value, GpuResult* result) {
	CmnResult localResult;

	Mtl4SemaphoreMetadata metadata = {};

	for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
		id<MTLSharedEvent> event = [gMtl4Context.device newSharedEvent];
		if (event == nil) {
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return {};
		}
		event.signaledValue = value;

		metadata.events[i] = event;
	}

	{
		CmnScopedStorageSyncLockWrite guard(&gMtl4SemaphoreStorage.sync);

		Mtl4Semaphore handle = cmnInsert(&gMtl4SemaphoreStorage.semaphores, metadata, &localResult);
		if (localResult != CMN_SUCCESS) {
			for (size_t i = 0; i < MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS; i++) {
				[metadata.events[i] release];
			}

			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return {};
		}

		CMN_SET_RESULT(result, GPU_SUCCESS);
		return mtl4HandleToGpuSemaphore(handle);
	}
}

void mtl4WaitSemaphore(GpuSemaphore sema, uint64_t value, GpuResult* result) {
	Mtl4Semaphore handle = mtl4GpuSemaphoreToHandle(sema);

	Mtl4SemaphoreMetadata* metadata = mtl4AcquireSemaphoreMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_SEMAPHORE_FOUND);
		return;
	}
	defer (mtl4ReleaseSemaphoreMetadata());

	for (size_t i = 0; i < metadata->lastSignalCount; i++) {
		[metadata->events[i] waitUntilSignaledValue:value timeoutMS:-1];
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4DestroySemaphore(GpuSemaphore sema) {
	(void)sema;
}

Mtl4SemaphoreMetadata* mtl4AcquireSemaphoreMetadataFrom(Mtl4Semaphore semaphore) {
	bool wasHandleValid;
	Mtl4SemaphoreMetadata* metadata = cmnStorageSyncAcquireResource(
		&gMtl4SemaphoreStorage.semaphores,
		&gMtl4SemaphoreStorage.sync,
		semaphore,
		&wasHandleValid
	);
	if (!wasHandleValid) {
		return nullptr;
	}

	return metadata;
}

void mtl4ReleaseSemaphoreMetadata(void) {
	cmnStorageSyncReleaseResource(&gMtl4SemaphoreStorage.sync);
}

