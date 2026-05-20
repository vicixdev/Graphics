#include "surfaces.h"

#include <lib/common/scoped_nsautoreleasepool.h>
#include <lib/metal4/context.h>
#include <lib/metal4/textures.h>
#include <lib/metal4/tables.h>

Mtl4SurfaceStorage gMtl4SurfaceStorage;

void mtl4InitSurfaceStorage(GpuResult* result) {

	CmnResult localResult;

	gMtl4SurfaceStorage.page = cmnCreatePage(16 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
	}

	gMtl4SurfaceStorage.arena = cmnPageToArena(gMtl4SurfaceStorage.page);

	cmnCreateHandleMap(&gMtl4SurfaceStorage.surfaces, cmnArenaAllocator(&gMtl4SurfaceStorage.arena), {}, &localResult);
	assert(localResult == CMN_SUCCESS && "If the page allocation succeded, then the handle map allocation should also succeed.");
}

void mtl4FiniSurfaceStorage(void) {
	CmnHandleMapIterator<Mtl4SurfaceMetadata> iter;
	cmnCreateHandleMapIterator(&gMtl4SurfaceStorage.surfaces, &iter);

	Mtl4SurfaceMetadata* surface;
	while (cmnIterate(&iter, &surface)) {
		mtl4DestroySurface(surface);
	}

	cmnDestroyPage(gMtl4SurfaceStorage.page);

	gMtl4SurfaceStorage = {};
}

GpuSurface mtl4CreateSurface(const GpuSurfaceDesc* desc, GpuResult* result) {
	assert(desc->target.type == GPU_SURFACE_COCOA && "Only the cocoa surface target is supported in the Metal 4 backend.");
	CmnScopedNSAutoreleasePool pool;

	CmnResult localResult;


	Mtl4SurfaceMetadata metadata = {};
	metadata.targetView = (NSView*)desc->target.cocoa.nsView;

	metadata.metalLayer = [CAMetalLayer new];
	if (metadata.metalLayer == nil) {
		CMN_SET_RESULT(result, GPU_COULD_NOT_CREATE_NATIVE_OBJECT);
		return {};
	}
	metadata.metalLayer.device = gMtl4Context.device;
	metadata.metalLayer.displaySyncEnabled = YES ? desc->type == GPU_SURFACE_VSYNC : NO;
	metadata.metalLayer.maximumDrawableCount = desc->framesInFlight;
	metadata.metalLayer.framebufferOnly = YES;
	metadata.metalLayer.drawableSize = CGSizeMake((float)desc->size[0], (float)desc->size[1]);
	metadata.metalLayer.pixelFormat = gMtl4GpuToMtlFormat[desc->format];
	metadata.metalLayer.allowsNextDrawableTimeout = YES;


	CmnScopedStorageSyncLockWrite guard(&gMtl4SurfaceStorage.sync);
	Mtl4Surface handle = cmnInsert(&gMtl4SurfaceStorage.surfaces, metadata, &localResult);
	if (localResult != CMN_SUCCESS) {
		[metadata.metalLayer release];

		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return {};
	}


	metadata.targetView.wantsLayer = YES;
	metadata.targetView.layer = metadata.metalLayer;


	CMN_SET_RESULT(result, GPU_SUCCESS);
	return mtl4HandleToGpuSurface(handle);
}

void mtl4ResizeSurface(GpuSurface surface, uint32_t size[2], GpuResult* result) {
	CmnScopedNSAutoreleasePool pool;

	Mtl4Surface handle = mtl4GpuSurfaceToHandle(surface);
	Mtl4SurfaceMetadata* metadata = mtl4AcquireSurfaceMetadata(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_SURFACE_FOUND);
		return;
	}
	defer (mtl4ReleaseSurfaceMetadata());

	metadata->metalLayer.drawableSize = CGSizeMake((float)size[0], (float)size[1]);

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4FreeSurface(GpuSurface surface) {
	// TODO: Implement in deletion manager
}

GpuTexture mtl4AcquireNextDrawable(GpuSurface surface, GpuResult* result) {
	CmnScopedNSAutoreleasePool pool;

	GpuResult localResult;


	Mtl4Surface handle = mtl4GpuSurfaceToHandle(surface);
	Mtl4SurfaceMetadata* metadata = mtl4AcquireSurfaceMetadata(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_SURFACE_FOUND);
		return {};
	}
	defer (mtl4ReleaseSurfaceMetadata());

	assert(metadata->currentDrawable == nil && metadata->currentDrawableTexture == 0 &&
		"It is not possible to acquire a new drawable if the last one has not been presented yet.");


	id<CAMetalDrawable> currentDrawable = [metadata->metalLayer nextDrawable];
	if (currentDrawable == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_DRAWABLES);
		return {};
	}
	[currentDrawable retain];

	GpuTexture currentDrawableTexture = mtl4CreateSurfaceTexture(currentDrawable, metadata->metalLayer.residencySet, &localResult);
	if (localResult != GPU_SUCCESS) {
		[currentDrawable release];

		CMN_SET_RESULT(result, localResult);
		return {};
	}


	metadata->currentDrawable = currentDrawable;
	metadata->currentDrawableTexture = currentDrawableTexture;

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return currentDrawableTexture;
}

void mtl4ReleaseDrawable(Mtl4SurfaceMetadata* metadata) {
	if (metadata->currentDrawableTexture != 0) {
		mtl4FreeTexture(metadata->currentDrawableTexture);
		metadata->currentDrawableTexture = 0;
	}

	if (metadata->currentDrawable != nil) {
		[metadata->currentDrawable release];
		metadata->currentDrawable = nil;
	}
}

// NOTE: Requires deletion lock on `gMtl4SurfaceStorage.sync`
void mtl4DestroySurface(Mtl4Surface surface) {
	bool wasHandleValid;
	Mtl4SurfaceMetadata* metadata = &cmnGet(&gMtl4SurfaceStorage.surfaces, surface, &wasHandleValid);
	if (!wasHandleValid) {
		return;
	}

	mtl4DestroySurface(metadata);

	cmnRemove(&gMtl4SurfaceStorage.surfaces, surface);
}

void mtl4DestroySurface(Mtl4SurfaceMetadata* metadata) {
	mtl4ReleaseDrawable(metadata);

	[metadata->metalLayer release];

	metadata->targetView.wantsLayer = NO;
	metadata->targetView.layer = nil;
}

Mtl4SurfaceMetadata* mtl4AcquireSurfaceMetadata(Mtl4Surface surface) {
	bool wasHandleValid;
	Mtl4SurfaceMetadata* metadata = cmnStorageSyncAcquireResource(
		&gMtl4SurfaceStorage.surfaces,
		&gMtl4SurfaceStorage.sync,
		surface,
		&wasHandleValid
	);
	if (!wasHandleValid) {
		return nullptr;
	}

	return metadata;
}

void mtl4ReleaseSurfaceMetadata(void) {
	cmnStorageSyncReleaseResource(&gMtl4SurfaceStorage.sync);
}


