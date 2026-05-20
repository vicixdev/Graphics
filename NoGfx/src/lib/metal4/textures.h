#ifndef MTL4_TEXTURES_H
#define MTL4_TEXTURES_H

#include <gpu/gpu.h>

#include <lib/common/page.h>
#include <lib/common/handle_map.h>
#include <lib/common/type_traits.h>
#include <lib/common/storage_sync.h>
#include <lib/common/keyed_chain.h>
#include <QuartzCore/QuartzCore.h>
#include <Metal/Metal.h>

typedef CmnHandle Mtl4Texture;
static_assert(sizeof(Mtl4Texture) == sizeof(GpuTexture), "Mtl4Texture and GpuTexture must be compatible");

typedef CmnKeyedChain<GpuViewDesc, id<MTLTexture>, 8> Mtl4TextureViews;
static_assert(sizeof(CmnKeyedChainNode<GpuViewDesc, id<MTLTexture>, 8>) <= 192, "");

typedef enum Mtl4TextureType {
	MTL4_TEXTURE_NORMAL,
	MTL4_TEXTURE_SURFACE,
} Mtl4TextureType;

typedef struct Mtl4TextureMetadata {
	// Atomic, Settable once
	bool			scheduledForDeletion;

	// Final
	Mtl4TextureType		type;
	
	// Final
	id<MTLTexture>		texture;

	// Final
	// NOTE: Used only if type is MTL4_TEXTURE_SURFACE
	id<CAMetalDrawable>	drawable;

	// Final
	// NOTE: Used only if type is MTL4_TEXTURE_SURFACE
	id<MTLResidencySet>	drawableResidencySet;

	// Final
	// NOTE: Zero if type is MTL4_TEXTURE_SURFACE
	GpuTextureDesc		descriptor;

	Mtl4TextureViews	relatedViews;
} Mtl4TextureMetadata;

typedef struct Mtl4TextureStorage {
	CmnPage		textureMetadataPage;
	CmnPage		textureViewsPage;

	CmnArena	textureMedatadaArena;
	CmnPool		textureViewsPool;

	CmnHandleMap	<Mtl4TextureMetadata>	textures;
	CmnStorageSync	sync;
} Mtl4TextureStorage;
extern Mtl4TextureStorage gMtl4TextureStorage;

void mtl4InitTextureStorage(GpuResult* result);
void mtl4FiniTextureStorage(void);

GpuTextureSizeAlign mtl4TextureSizeAlign(const GpuTextureDesc* desc, GpuResult* result);
GpuTexture mtl4CreateTexture(const GpuTextureDesc* desc, void* ptrGpu, GpuResult* result);
GpuTexture mtl4CreateSurfaceTexture(id<CAMetalDrawable> drawable, id<MTLResidencySet> residencySet, GpuResult* result);
GpuTextureDescriptor mtl4TextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result);
GpuTextureDescriptor mtl4RWTextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result);

void mtl4FreeTexture(GpuTexture texture);
bool mtl4IsTextureScheduledForDeletion(Mtl4Texture texture);

Mtl4TextureMetadata* mtl4AcquireTextureMetadataFrom(Mtl4Texture texture);
void mtl4ReleaseTextureMetadata(void);

inline Mtl4Texture mtl4GpuTextureToHadle(GpuTexture texture) {
	return *(Mtl4Texture*)&texture;
}

inline GpuTexture mtl4HandleToGpuTexture(Mtl4Texture handle) {
	return *(GpuTexture*)&handle;
}

inline GpuTextureDescriptor mtl4TextureResourceIdToDescriptor(MTLResourceID id) {
	GpuTextureDescriptor desc;
	desc.data[0] = id._impl;
	desc.data[1] = 0;
	desc.data[2] = 0;
	desc.data[3] = 0;

	return desc;
}

MTLTextureDescriptor* mtl4GpuTextureDescToMtl(const GpuTextureDesc* desc, MTLResourceOptions resourceOptions);
MTLTextureViewDescriptor* mtl4GpuViewDescToMtl(id<MTLTexture> referenceTexture, const GpuViewDesc* desc);

void mtl4AssociateViewToTexture(Mtl4TextureMetadata* metadata, id<MTLTexture> view, const GpuViewDesc* desc, GpuResult* result);

// NOTE: Requires deletion lock on gMtl4TextureStorage.sync
void mtl4DestroyAssociatedTextureViews(Mtl4TextureMetadata* metadata);

// NOTE: Requires deletion lock on gMtl4TextureStorage.sync
void mtl4DestroyTexture(Mtl4Texture texture);

template <>
struct CmnTypeTraits<GpuViewDesc> {
	static bool eq(const GpuViewDesc& left, const GpuViewDesc& right) {
		return memcmp(&left, &right, sizeof(GpuViewDesc)) == 0;
	}

	// cmp compares two values of type T.
	static CmnCmp cmp(const GpuViewDesc& left, const GpuViewDesc& right) {
		return (CmnCmp)memcmp(&left, &right, sizeof(GpuViewDesc));
	}

	// hash computes the hash code for type T.
	static size_t hash(const GpuViewDesc& value) {
		(void)value;
		assert(false && "GpuViewDesc is not hashable");
	}
};

#endif // MTL4_TEXTURES_H

