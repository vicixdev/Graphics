#include "depthstencilstates.h"

#include <gpu/gpu.h>
#include <lib/common/scoped_nsautoreleasepool.h>
#include <lib/metal4/context.h>
#include <lib/metal4/tables.h>
#include <lib/metal4/deletion_manager.h>

Mtl4DepthStencilStateStorage gMtl4DepthStencilStateStorage;

void mtl4InitDepthStencilStorage(GpuResult* result) {
	CmnResult localResult;
	gMtl4DepthStencilStateStorage.page = cmnCreatePage(1024 * 1024 * 32, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult!= CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	gMtl4DepthStencilStateStorage.arena = cmnPageToArena(gMtl4DepthStencilStateStorage.page);

	cmnCreateHandleMap(
		&gMtl4DepthStencilStateStorage.depthStencilStates,
		cmnArenaAllocator(&gMtl4DepthStencilStateStorage.arena),
		{},
		&localResult);
	assert(localResult == CMN_SUCCESS && "If the page creation succeeded, the handle map creation should succeed as well.");
}

void mtl4FiniDepthStencilStorage(void) {
	cmnDestroyPage(gMtl4DepthStencilStateStorage.page);
}

GpuDepthStencilState mtl4CreateDepthStencilState(const GpuDepthStencilDesc* desc, GpuResult* result) {
	CmnScopedNSAutoreleasePool pool;

	CmnResult localResult;

	MTLDepthStencilDescriptor* depthStencilDescriptor = mtl4GpuDepthStencilDescToMetal(desc);
	id<MTLDepthStencilState> depthStencilState = [gMtl4Context.device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
	if (depthStencilState == nil) {
		CMN_SET_RESULT(result, GPU_COULD_NOT_CREATE_NATIVE_OBJECT);
		return {};
	}

	Mtl4DepthStencilStateMetadata metadata = {};
	metadata.desc = *desc;
	metadata.depthStencilState = depthStencilState;

	CmnScopedStorageSyncLockWrite guard(&gMtl4DepthStencilStateStorage.sync);

	Mtl4DepthStencilState handle = cmnInsert(&gMtl4DepthStencilStateStorage.depthStencilStates, metadata, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return 0;
	}

	return mtl4HandleToGpuDepthStencilState(handle);
}

void mtl4FreeDepthStencilState(GpuDepthStencilState state) {
	CmnScopedNSAutoreleasePool pool;

	Mtl4DepthStencilState handle = mtl4GpuDepthStencilStateToHandle(state);
	Mtl4DepthStencilStateMetadata* metadata = mtl4AcquireDepthStencilStateMetadataFrom(handle);
	if (metadata == nullptr) {
		return;
	}
	cmnAtomicStore(&metadata->isScheduledForDeletion, true);

	mtl4ReleaseDepthStencilStateMetadata();
	mtl4ScheduleDepthStencilStateForDeleltion(handle);
	mtl4CheckForResourceDeletion();
}

MTLDepthStencilDescriptor* mtl4GpuDepthStencilDescToMetal(const GpuDepthStencilDesc* desc) {
	MTLDepthStencilDescriptor* metalDesc = [MTLDepthStencilDescriptor new];

	metalDesc.frontFaceStencil = [[MTLStencilDescriptor new] autorelease];
	metalDesc.frontFaceStencil.stencilCompareFunction = gMtl4GpuOpToMtlCompareFunction[desc->stencilFront.test];
	metalDesc.frontFaceStencil.stencilFailureOperation = gMtl4GpuOpToMtlStencilOperation[desc->stencilFront.failOp];
	metalDesc.frontFaceStencil.depthFailureOperation = gMtl4GpuOpToMtlStencilOperation[desc->stencilFront.depthFailOp];
	metalDesc.frontFaceStencil.depthStencilPassOperation = gMtl4GpuOpToMtlStencilOperation[desc->stencilFront.passOp];
	metalDesc.frontFaceStencil.readMask = desc->stencilReadMask;
	metalDesc.frontFaceStencil.writeMask = desc->stencilWriteMask;

	metalDesc.backFaceStencil = [[MTLStencilDescriptor new] autorelease];
	metalDesc.backFaceStencil.stencilCompareFunction = gMtl4GpuOpToMtlCompareFunction[desc->stencilBack.test];
	metalDesc.backFaceStencil.stencilFailureOperation = gMtl4GpuOpToMtlStencilOperation[desc->stencilBack.failOp];
	metalDesc.backFaceStencil.depthFailureOperation = gMtl4GpuOpToMtlStencilOperation[desc->stencilBack.depthFailOp];
	metalDesc.backFaceStencil.depthStencilPassOperation = gMtl4GpuOpToMtlStencilOperation[desc->stencilBack.passOp];
	metalDesc.backFaceStencil.readMask = desc->stencilReadMask;
	metalDesc.backFaceStencil.writeMask = desc->stencilWriteMask;

	metalDesc.depthCompareFunction = gMtl4GpuOpToMtlCompareFunction[desc->depthTest];
	metalDesc.depthWriteEnabled = desc->depthMode & GPU_DEPTH_WRITE;

	return metalDesc;
}

void mtl4DestroyDepthStencilState(Mtl4DepthStencilState state) {
	bool wasHandleValid;
	Mtl4DepthStencilStateMetadata* metadata = &cmnGet(&gMtl4DepthStencilStateStorage.depthStencilStates, state, &wasHandleValid);
	if (!wasHandleValid) {
		return;
	}

	[metadata->depthStencilState release];

	cmnRemove(&gMtl4DepthStencilStateStorage.depthStencilStates, state);
}

bool mtl4IsDepthStencilStateScheduledForDeletion(Mtl4DepthStencilState state) {
	Mtl4DepthStencilStateMetadata* metadata = mtl4AcquireDepthStencilStateMetadataFrom(state);
	if (metadata == nullptr) {
		return false;
	}
	defer (mtl4ReleaseDepthStencilStateMetadata());

	return cmnAtomicLoad(&metadata->isScheduledForDeletion);
}

Mtl4DepthStencilStateMetadata* mtl4AcquireDepthStencilStateMetadataFrom(Mtl4DepthStencilState handle) {
	bool didFindResource;
	Mtl4DepthStencilStateMetadata* metadata = cmnStorageSyncAcquireResource(
		&gMtl4DepthStencilStateStorage.depthStencilStates,
		&gMtl4DepthStencilStateStorage.sync,
		handle,
		&didFindResource
	);
	if (!didFindResource) {
		return nullptr;
	}

	return metadata;
}

void mtl4ReleaseDepthStencilStateMetadata(void) {
	cmnStorageSyncReleaseResource(&gMtl4DepthStencilStateStorage.sync);
}


