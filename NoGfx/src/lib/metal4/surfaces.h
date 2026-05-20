#ifndef MTL4_SURFACE_H
#define MTL4_SURFACE_H

#include <gpu/gpu.h>
#include <lib/common/page.h>
#include <lib/common/handle_map.h>
#include <lib/common/storage_sync.h>

#include <Cocoa/Cocoa.h>
#include <QuartzCore/QuartzCore.h>

typedef CmnHandle Mtl4Surface;

typedef struct Mtl4SurfaceMetadata {
	NSView*			targetView;
	CAMetalLayer*		metalLayer;

	id<CAMetalDrawable>	currentDrawable;
	GpuTexture		currentDrawableTexture;
} Mtl4SurfaceMetadata;

typedef struct Mtl4SurfaceStorage {
	CmnPage					page;
	CmnArena				arena;

	CmnHandleMap	<Mtl4SurfaceMetadata>	surfaces;
	CmnStorageSync				sync;
} Mtl4SurfaceStorage;
extern Mtl4SurfaceStorage gMtl4SurfaceStorage;

void mtl4InitSurfaceStorage(GpuResult* result);
void mtl4FiniSurfaceStorage(void);

GpuSurface mtl4CreateSurface(const GpuSurfaceDesc* desc, GpuResult* result);
void mtl4ResizeSurface(GpuSurface surface, uint32_t size[2], GpuResult* result);
void mtl4FreeSurface(GpuSurface surface);
GpuTexture mtl4AcquireNextDrawable(GpuSurface surface, GpuResult* result);

void mtl4ReleaseDrawable(Mtl4SurfaceMetadata* metadata);

// NOTE: Requires deletion lock on `gMtl4SurfaceStorage.sync`
void mtl4DestroySurface(Mtl4Surface surface);
void mtl4DestroySurface(Mtl4SurfaceMetadata* metadata);

Mtl4SurfaceMetadata* mtl4AcquireSurfaceMetadata(Mtl4Surface surface);
void mtl4ReleaseSurfaceMetadata(void);

inline Mtl4Surface mtl4GpuSurfaceToHandle(GpuSurface surface) {
	return *(Mtl4Surface*)&surface;
}
inline GpuSurface mtl4HandleToGpuSurface(Mtl4Surface handle) {
	return *(GpuSurface*)&handle;
}

#endif // MTL4_SURFACE_H

