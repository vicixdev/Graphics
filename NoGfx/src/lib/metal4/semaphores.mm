#include "semaphores.h"

#include <lib/common/scoped_nsautoreleasepool.h>
#include <lib/metal4/context.h>
#include <lib/metal4/deletion_manager.h>

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
	CmnScopedNSAutoreleasePool pool;
	CmnResult localResult;

	Mtl4SemaphoreMetadata metadata = {};

	metadata.event = [gMtl4Context.device newSharedEvent];
	if (metadata.event == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return {};
	}
	metadata.event.signaledValue = value;

	{
		CmnScopedStorageSyncLockWrite guard(&gMtl4SemaphoreStorage.sync);

		Mtl4Semaphore handle = cmnInsert(&gMtl4SemaphoreStorage.semaphores, metadata, &localResult);
		if (localResult != CMN_SUCCESS) {
			[metadata.event release];

			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return {};
		}

		CMN_SET_RESULT(result, GPU_SUCCESS);
		return mtl4HandleToGpuSemaphore(handle);
	}
}

void mtl4WaitSemaphore(GpuSemaphore sema, uint64_t value, GpuResult* result) {
	CmnScopedNSAutoreleasePool pool;

	Mtl4Semaphore handle = mtl4GpuSemaphoreToHandle(sema);

	Mtl4SemaphoreMetadata* metadata = mtl4AcquireSemaphoreMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_SEMAPHORE_FOUND);
		return;
	}
	defer (mtl4ReleaseSemaphoreMetadata());

	[metadata->event waitUntilSignaledValue:value timeoutMS:-1];

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4FreeSemaphore(GpuSemaphore sema) {
	CmnScopedNSAutoreleasePool pool;

	Mtl4Semaphore handle = mtl4GpuSemaphoreToHandle(sema);
	Mtl4SemaphoreMetadata* metadata = mtl4AcquireSemaphoreMetadataFrom(handle);
	if (metadata == nullptr) {
		return;
	}
	cmnAtomicStore(&metadata->isScheduledForDeletion, true);

	mtl4ReleaseSemaphoreMetadata();
	mtl4ScheduleSemaphoreForDeletion(handle);
	mtl4CheckForResourceDeletion();
}

void mtl4DestroySemaphore(Mtl4Semaphore semaphore) {
	bool wasHandleValid;
	Mtl4SemaphoreMetadata* metadata = &cmnGet(&gMtl4SemaphoreStorage.semaphores, semaphore, &wasHandleValid);
	if (!wasHandleValid) {
		return;
	}

	[metadata->event release];

	cmnRemove(&gMtl4SemaphoreStorage.semaphores, semaphore);
}

bool mtl4IsSemaphoreScheduledForDeletion(Mtl4Semaphore semaphore) {
	Mtl4SemaphoreMetadata* metadata = mtl4AcquireSemaphoreMetadataFrom(semaphore);
	if (metadata == nullptr) {
		return false;
	}
	defer (mtl4ReleaseSemaphoreMetadata());

	return cmnAtomicLoad(&metadata->isScheduledForDeletion);
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

