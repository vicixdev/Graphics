#include "deletion_manager.h"

Mtl4DeletionManager gMtl4DeletionManager;

void mtl4InitDeletionManager(GpuResult* result) {
	CmnResult localResult;

	gMtl4DeletionManager.page = cmnCreatePage(32 * 1024 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	gMtl4DeletionManager.arena = cmnPageToArena(gMtl4DeletionManager.page);
	CmnAllocator arenaAllocator = cmnArenaAllocator(&gMtl4DeletionManager.arena);

	cmnCreateExponentialArray(&gMtl4DeletionManager.allocations, arenaAllocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	cmnCreateExponentialArray(&gMtl4DeletionManager.textures, arenaAllocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	cmnCreateExponentialArray(&gMtl4DeletionManager.pipelines, arenaAllocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	cmnCreateExponentialArray(&gMtl4DeletionManager.surfaces, arenaAllocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	cmnCreateExponentialArray(&gMtl4DeletionManager.depthStencilStates, arenaAllocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	cmnCreateExponentialArray(&gMtl4DeletionManager.blendStates, arenaAllocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	cmnCreateExponentialArray(&gMtl4DeletionManager.semaphores, arenaAllocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4FiniDeletionManager(void) {
	cmnDestroyPage(gMtl4DeletionManager.page);

	gMtl4DeletionManager = {};
}

void mtl4ScheduleAllocationForDeletion(Mtl4AllocationHandle allocation) {
	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFrom(allocation, nullptr);
	if (metadata == nullptr) {
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	CmnScopedMutex guard(&gMtl4DeletionManager.allocationsMutex);
	cmnAppend(&gMtl4DeletionManager.allocations, allocation, nullptr);

	// TODO: Not actually accurate, since it could be more with the alignment.
	gMtl4DeletionManager.bytesToDeallocate += metadata->size;
}

void mtl4ScheduleTextureForDeletion(Mtl4Texture texture) {
	CmnScopedMutex guard(&gMtl4DeletionManager.texturesMutex);
	cmnAppend(&gMtl4DeletionManager.textures, texture, nullptr);
	gMtl4DeletionManager.texturesToDeallocate += 1;
}

void mtl4SchedulePipelineForDeletion(Mtl4Pipeline pipeline) {
	CmnScopedMutex guard(&gMtl4DeletionManager.pipelinesMutex);
	cmnAppend(&gMtl4DeletionManager.pipelines, pipeline, nullptr);
	gMtl4DeletionManager.pipelinesToDeallocate += 1;
}

void mtl4ScheduleSurfaceForDeletion(Mtl4Surface surface) {
	CmnScopedMutex guard(&gMtl4DeletionManager.surfacesMutex);
	cmnAppend(&gMtl4DeletionManager.surfaces, surface, nullptr);
	gMtl4DeletionManager.surfacesToDeallocate += 1;
}

void mtl4ScheduleDepthStencilStateForDeleltion(Mtl4DepthStencilState depthStencil) {
	CmnScopedMutex guard(&gMtl4DeletionManager.depthStencilStatesMutex);
	cmnAppend(&gMtl4DeletionManager.depthStencilStates, depthStencil, nullptr);
	gMtl4DeletionManager.depthStencilStatesToDeallocate += 1;
}

void mtl4ScheduleBlendStateForDeletion(Mtl4BlendState blend) {
	CmnScopedMutex guard(&gMtl4DeletionManager.blendStatesMutex);
	cmnAppend(&gMtl4DeletionManager.blendStates, blend, nullptr);
	gMtl4DeletionManager.blendStatesToDeallocate += 1;
}

void mtl4ScheduleSemaphoreForDeletion(Mtl4Semaphore semaphore) {
	CmnScopedMutex guard(&gMtl4DeletionManager.semaphoreMutex);
	cmnAppend(&gMtl4DeletionManager.semaphores, semaphore, nullptr);
	gMtl4DeletionManager.semaphoresToDeallocate += 1;
}

bool mtl4ShouldDeleteScheduledResources(void) {
	return mtl4ShouldDeleteScheduledTextures() ||
		mtl4ShouldDeleteScheduledAllocations() ||
		mtl4ShouldDeleteScheduledPipelines() ||
		mtl4ShouldDeleteScheduledSurfaces() ||
		mtl4ShouldDeleteScheduledDepthStencilStates() ||
		mtl4ShouldDeleteScheduledBlendStates() ||
		mtl4ShouldDeleteScheduledSemaphores();
}

bool mtl4ShouldDeleteScheduledAllocations(void) {
	CmnScopedMutex guard(&gMtl4DeletionManager.allocationsMutex);
	return gMtl4DeletionManager.bytesToDeallocate >= 10 * 1024 * 1024;
}

bool mtl4ShouldDeleteScheduledTextures(void) {
	CmnScopedMutex guard(&gMtl4DeletionManager.texturesMutex);
	return gMtl4DeletionManager.texturesToDeallocate >= 128;
}

bool mtl4ShouldDeleteScheduledPipelines(void) {
	CmnScopedMutex guard(&gMtl4DeletionManager.pipelinesMutex);
	return gMtl4DeletionManager.pipelinesToDeallocate >= 64;
}

bool mtl4ShouldDeleteScheduledSurfaces(void) {
	CmnScopedMutex guard(&gMtl4DeletionManager.surfacesMutex);
	return gMtl4DeletionManager.surfacesToDeallocate >= 2;
}

bool mtl4ShouldDeleteScheduledDepthStencilStates(void) {
	CmnScopedMutex guard(&gMtl4DeletionManager.depthStencilStatesMutex);
	return gMtl4DeletionManager.depthStencilStatesToDeallocate >= 64;
}

bool mtl4ShouldDeleteScheduledBlendStates(void) {
	CmnScopedMutex guard(&gMtl4DeletionManager.blendStatesMutex);
	return gMtl4DeletionManager.blendStatesToDeallocate >= 128;
}

bool mtl4ShouldDeleteScheduledSemaphores(void) {
	CmnScopedMutex guard(&gMtl4DeletionManager.semaphoreMutex);
	return gMtl4DeletionManager.semaphoresToDeallocate >= 64;
}

void mtl4DeleteScheduledResources(void) {
	if (mtl4ShouldDeleteScheduledAllocations()) {
		mtl4DeleteScheduledAllocations();
	}

	if (mtl4ShouldDeleteScheduledTextures()) {
		mtl4DeleteScheduledTextures();
	}

	if (mtl4ShouldDeleteScheduledPipelines()) {
		mtl4DeleteScheduledPipelines();
	}

	if (mtl4ShouldDeleteScheduledSurfaces()) {
		mtl4DeleteScheduledSurfaces();
	}

	if (mtl4ShouldDeleteScheduledDepthStencilStates()) {
		mtl4DeleteScheduledDepthStencilStates();
	}
	
	if (mtl4ShouldDeleteScheduledBlendStates()) {
		mtl4DeleteScheduledBlendStates();
	}

	if (mtl4ShouldDeleteScheduledSemaphores()) {
		mtl4DeleteScheduledSemaphores();
	}
}

void mtl4DeleteScheduledAllocations(void) {
	CmnScopedStorageSyncDeletionLock guard(&gMtl4AllocationStorage.sync);
	CmnScopedMutex guardd(&gMtl4DeletionManager.allocationsMutex);

	for (size_t i = 0; i < gMtl4DeletionManager.allocations.length; i++) {
		mtl4DestroyAllocation(gMtl4DeletionManager.allocations[i]);
	}

	cmnResize(&gMtl4DeletionManager.allocations, 0, nullptr);
	gMtl4DeletionManager.bytesToDeallocate = 0;
}

void mtl4DeleteScheduledTextures(void) {
	CmnScopedStorageSyncDeletionLock guard(&gMtl4TextureStorage.sync);
	CmnScopedMutex guardd(&gMtl4DeletionManager.texturesMutex);

	for (size_t i = 0; i < gMtl4DeletionManager.textures.length; i++) {
		mtl4DestroyTexture(gMtl4DeletionManager.textures[i]);
	}

	cmnResize(&gMtl4DeletionManager.textures, 0, nullptr);
	gMtl4DeletionManager.texturesToDeallocate = 0;
}

void mtl4DeleteScheduledPipelines(void) {
	CmnScopedStorageSyncDeletionLock guard(&gMtl4PipelineStorage.sync);
	CmnScopedMutex guardd(&gMtl4DeletionManager.pipelinesMutex);

	for (size_t i = 0; i < gMtl4DeletionManager.pipelines.length; i++) {
		mtl4DestroyPipeline(gMtl4DeletionManager.pipelines[i]);
	}

	cmnResize(&gMtl4DeletionManager.pipelines, 0, nullptr);
	gMtl4DeletionManager.pipelinesToDeallocate = 0;
}

void mtl4DeleteScheduledSurfaces(void) {
	CmnScopedStorageSyncDeletionLock guard(&gMtl4SurfaceStorage.sync);
	CmnScopedMutex guardd(&gMtl4DeletionManager.surfacesMutex);

	for (size_t i = 0; i < gMtl4DeletionManager.surfaces.length; i++) {
		mtl4DestroySurface(gMtl4DeletionManager.surfaces[i]);
	}

	cmnResize(&gMtl4DeletionManager.surfaces, 0, nullptr);
	gMtl4DeletionManager.surfacesToDeallocate = 0;
}

void mtl4DeleteScheduledDepthStencilStates(void) {
	CmnScopedStorageSyncDeletionLock guard(&gMtl4DepthStencilStateStorage.sync);
	CmnScopedMutex guardd(&gMtl4DeletionManager.depthStencilStatesMutex);

	for (size_t i = 0; i < gMtl4DeletionManager.depthStencilStates.length; i++) {
		mtl4DestroyDepthStencilState(gMtl4DeletionManager.depthStencilStates[i]);
	}

	cmnResize(&gMtl4DeletionManager.depthStencilStates, 0, nullptr);
	gMtl4DeletionManager.depthStencilStatesToDeallocate = 0;
}

void mtl4DeleteScheduledBlendStates(void) {
	CmnScopedStorageSyncDeletionLock guard(&gMtl4BlendStateStorage.sync);
	CmnScopedMutex guardd(&gMtl4DeletionManager.blendStatesMutex);

	for (size_t i = 0; i < gMtl4DeletionManager.blendStates.length; i++) {
		mtl4DestroyBlendState(gMtl4DeletionManager.blendStates[i]);
	}

	cmnResize(&gMtl4DeletionManager.blendStates, 0, nullptr);
	gMtl4DeletionManager.blendStatesToDeallocate = 0;
}

void mtl4DeleteScheduledSemaphores(void) {
	CmnScopedStorageSyncDeletionLock guard(&gMtl4SemaphoreStorage.sync);
	CmnScopedMutex guardd(&gMtl4DeletionManager.semaphoreMutex);

	for (size_t i = 0; i < gMtl4DeletionManager.semaphores.length; i++) {
		mtl4DestroySemaphore(gMtl4DeletionManager.semaphores[i]);
	}

	cmnResize(&gMtl4DeletionManager.semaphores, 0, nullptr);
	gMtl4DeletionManager.semaphoresToDeallocate = 0;
}

void mtl4CheckForResourceDeletion(void) {
	uint32_t expected = 0u;
	if (!cmnAtomicCompareExchangeStrong(&gMtl4DeletionManager.isDeleting, &expected, 1u, CMN_ACQ_REL, CMN_ACQUIRE)) {
		return;
	}
	defer (cmnAtomicStore(&gMtl4DeletionManager.isDeleting, 0u, CMN_RELEASE));

	while (mtl4ShouldDeleteScheduledResources()) {
		mtl4DeleteScheduledResources();
	}
}
 
