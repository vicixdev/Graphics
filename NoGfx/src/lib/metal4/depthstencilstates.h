#ifndef MTL4_DEPTHSTENCILSTATES_H
#define MTL4_DEPTHSTENCILSTATES_H

#include <gpu/gpu.h>
#include <lib/common/page.h>
#include <lib/common/handle_map.h>
#include <lib/common/storage_sync.h>
#include <Metal/Metal.h>

typedef CmnHandle Mtl4DepthStencilState;

typedef struct Mtl4DepthStencilStateMetadata {
	GpuDepthStencilDesc		desc;

	id<MTLDepthStencilState>	depthStencilState;
} Mtl4DepthStencilStateMetadata;

typedef struct Mtl4DepthStencilStateStorage {
	CmnPage		page;
	CmnArena	arena;

	CmnHandleMap	<Mtl4DepthStencilStateMetadata>	depthStencilStates;
	CmnStorageSync	sync;
} Mtl4DepthStencilStateStorage;
extern Mtl4DepthStencilStateStorage gMtl4DepthStencilStateStorage;

void mtl4InitDepthStencilStorage(GpuResult* result);
void mtl4FiniDepthStencilStorage(void);

GpuDepthStencilState mtl4CreateDepthStencilState(const GpuDepthStencilDesc* desc, GpuResult* result);
void mtl4FreeDepthStencilState(GpuDepthStencilState state);

MTLDepthStencilDescriptor* mtl4GpuDepthStencilDescToMetal(const GpuDepthStencilDesc* desc);
void mtl4ReleaseMetalDepthStencilDesc(MTLDepthStencilDescriptor* desc);

Mtl4DepthStencilStateMetadata* mtl4AcquireDepthStencilStateMetadataFrom(Mtl4DepthStencilState handle);
void mtl4ReleaseDepthStencilStateMetadata(void);

inline GpuDepthStencilState mtl4HandleToGpuDepthStencilState(Mtl4DepthStencilState handle) {
	return *(GpuDepthStencilState*)&handle;
}
inline Mtl4DepthStencilState mtl4GpuDepthStencilStateToHandle(GpuDepthStencilState state) {
	return *(Mtl4DepthStencilState*)&state;
}

#endif // MTL4_DEPTHSTENCILSTATES_H

