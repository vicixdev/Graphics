#include "blend_states.h"

#include <lib/common/scoped_nsautoreleasepool.h>
#include <lib/metal4/deletion_manager.h>

Mtl4BlendStateStorage gMtl4BlendStateStorage;

void mtl4InitBlendStateStorage(GpuResult* result) {
	CmnResult localResult;

	gMtl4BlendStateStorage.page = cmnCreatePage(1024 * 1024 * 32, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult!= CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	gMtl4BlendStateStorage.arena = cmnPageToArena(gMtl4BlendStateStorage.page);

	cmnCreateHandleMap(
		&gMtl4BlendStateStorage.blendStates,
		cmnArenaAllocator(&gMtl4BlendStateStorage.arena),
		{},
		&localResult);
	assert(localResult == CMN_SUCCESS && "If the page creation succeeded, the handle map creation should succeed as well.");
}

void mtl4FiniBlendStateStorage(void) {
	cmnDestroyPage(gMtl4BlendStateStorage.page);
}

GpuBlendState mtl4CreateBlendState(const GpuBlendDesc* desc, GpuResult* result) {
	CmnScopedNSAutoreleasePool pool;

	CmnResult localResult;

	Mtl4BlendStateMetadata metadata = {};
	metadata.desc = *desc;

	CmnScopedStorageSyncLockWrite guard(&gMtl4BlendStateStorage.sync);
	Mtl4BlendState handle = cmnInsert(&gMtl4BlendStateStorage.blendStates, metadata, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return {};
	}
	
	return mtl4HandleToGpuBlendState(handle);
}

void mtl4FreeBlendState(GpuBlendState state) {
	CmnScopedNSAutoreleasePool pool;

	Mtl4BlendState handle = mtl4GpuBlendStateToHandle(state);
	Mtl4BlendStateMetadata* metadata = mtl4AcquireBlendStateMetadata(handle);
	if (metadata == nullptr) {
		return;
	}
	cmnAtomicStore(&metadata->isScheduledForDeletion, true);

	mtl4ReleaseBlendStateMetadata();
	mtl4ScheduleBlendStateForDeletion(handle);
	mtl4CheckForResourceDeletion();
}

void mtl4DestroyBlendState(Mtl4BlendState state) {
	cmnRemove(&gMtl4BlendStateStorage.blendStates, state);
}

bool mtl4IsBlendStateScheduledForDeletion(Mtl4BlendState state) {
	Mtl4BlendStateMetadata* metadata = mtl4AcquireBlendStateMetadata(state);
	if (metadata == nullptr) {
		return false;
	}
	defer (mtl4ReleaseBlendStateMetadata());

	return cmnAtomicLoad(&metadata->isScheduledForDeletion);
}

Mtl4BlendStateMetadata* mtl4AcquireBlendStateMetadata(Mtl4BlendState handle) {
	bool wasHandleValid;
	Mtl4BlendStateMetadata* metadata = cmnStorageSyncAcquireResource(
		&gMtl4BlendStateStorage.blendStates,
		&gMtl4BlendStateStorage.sync,
		handle,
		&wasHandleValid
	);

	if (!wasHandleValid) {
		return nullptr;
	} else {
		return metadata;
	}
}

void mtl4ReleaseBlendStateMetadata(void) {
	cmnStorageSyncReleaseResource(&gMtl4BlendStateStorage.sync);
}

