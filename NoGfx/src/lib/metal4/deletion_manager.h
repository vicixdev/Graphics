#ifndef MTL4_DELETION_MANAGER_H
#define MTL4_DELETION_MANAGER_H

#include <lib/common/page.h>
#include <lib/common/exponential_array.h>
#include <lib/common/mutex.h>

#include <lib/metal4/allocation.h>
#include <lib/metal4/textures.h>
#include <lib/metal4/pipelines.h>

typedef struct Mtl4DeletionManager {
	CmnPage		page;
	CmnArena	arena;

	// Atomic
	uint32_t	isDeleting;

	// Locked by allocationsMutex
	size_t		bytesToDeallocate;
	// Locked by allocationsMutex
	CmnExponentialArray	<Mtl4AllocationHandle>	allocations;
	CmnMutex	allocationsMutex;

	// Locked by texturesMutex
	size_t		texturesToDeallocate;
	// Locked by texturesMutex
	CmnExponentialArray	<Mtl4Texture>	textures;
	CmnMutex	texturesMutex;

	// Locked by pipelinesMutex
	size_t		pipelinesToDeallocate;
	// Locked by pipelinesMutex
	CmnExponentialArray	<Mtl4Pipeline>	pipelines;
	CmnMutex	pipelinesMutex;
} Mtl4DeletionManager;
extern Mtl4DeletionManager gMtl4DeletionManager;

void mtl4InitDeletionManager(GpuResult* result);
void mtl4FiniDeletionManager(void);

void mtl4ScheduleAllocationForDeletion(Mtl4AllocationHandle allocation);
void mtl4ScheduleTextureForDeletion(Mtl4Texture texture);
void mtl4SchedulePipelineForDeletion(Mtl4Pipeline pipeline);

bool mtl4ShouldDeleteScheduledResources(void);
bool mtl4ShouldDeleteScheduledAllocations(void);
bool mtl4ShouldDeleteScheduledTextures(void);
bool mtl4ShouldDeleteScheduledPipelines(void);

void mtl4DeleteScheduledResources(void);
void mtl4DeleteScheduledAllocations(void);
void mtl4DeleteScheduledTextures(void);
void mtl4DeleteScheduledPipelines(void);

void mtl4CheckForResourceDeletion(void);

#endif // MTL4_DELETION_MANAGER_H

