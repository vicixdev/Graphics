#ifndef MTL4_BLENDSTATES_H
#define MTL4_BLENDSTATES_H

#include <gpu/gpu.h>
#include <lib/common/page.h>
#include <lib/common/handle_map.h>
#include <lib/common/storage_sync.h>

typedef CmnHandle Mtl4BlendState;

typedef struct Mtl4BlendStateMetadata {
	bool		isScheduledForDeletion;
	GpuBlendDesc	desc;
} Mtl4BlendStateMetadata;

typedef struct Mtl4BlendStateStorage {
	CmnPage		page;
	CmnArena	arena;

	CmnHandleMap	<Mtl4BlendStateMetadata>	blendStates;
	CmnStorageSync	sync;
} Mtl4BlendStateStorage;
extern Mtl4BlendStateStorage gMtl4BlendStateStorage;

void mtl4InitBlendStateStorage(GpuResult* result);
void mtl4FiniBlendStateStorage(void);

GpuBlendState mtl4CreateBlendState(const GpuBlendDesc* desc, GpuResult* result);
void mtl4FreeBlendState(GpuBlendState state);

// NOTE: Requires deletion lock on gMtl4BlendStateStorage.sync
void mtl4DestroyBlendState(Mtl4BlendState state);

bool mtl4IsBlendStateScheduledForDeletion(Mtl4BlendState state);

Mtl4BlendStateMetadata* mtl4AcquireBlendStateMetadata(Mtl4BlendState handle);
void mtl4ReleaseBlendStateMetadata(void);

inline Mtl4BlendState mtl4GpuBlendStateToHandle(GpuBlendState blendState) {
	return *(Mtl4BlendState*)&blendState;
}

inline GpuBlendState mtl4HandleToGpuBlendState(Mtl4BlendState handle) {
	return *(GpuBlendState*)&handle;
}

#endif // MTL4_BLENDSTATES_H

