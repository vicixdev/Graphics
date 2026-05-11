#include "textures.h"

#include <lib/common/memory.h>
#include <lib/common/scoped_nsautoreleasepool.h>
#include <lib/metal4/tables.h>
#include <lib/metal4/context.h>
#include <lib/metal4/allocation.h>
#include <lib/metal4/deletion_manager.h>

Mtl4TextureStorage gMtl4TextureStorage;

void mtl4InitTextureStorage(GpuResult* result) {
	CmnResult localResult;

	gMtl4TextureStorage.textureMetadataPage = cmnCreatePage(4 * 1024 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	gMtl4TextureStorage.textureViewsPage = cmnCreatePage(4 * 1024 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	gMtl4TextureStorage.textureMedatadaArena = cmnPageToArena(gMtl4TextureStorage.textureMetadataPage);
	gMtl4TextureStorage.textureViewsPool = cmnPageToPool(gMtl4TextureStorage.textureViewsPage, 192);

	CmnAllocator allocator;
	allocator = cmnArenaAllocator(&gMtl4TextureStorage.textureMedatadaArena);

	cmnCreateHandleMap(&gMtl4TextureStorage.textures, allocator, {}, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4FiniTextureStorage(void) {
	cmnDestroyPage(gMtl4TextureStorage.textureMetadataPage);

	gMtl4TextureStorage = {};
}

GpuTexture mtl4CreateTexture(const GpuTextureDesc* desc, void* ptrGpu, GpuResult* result) {
	CmnScopedNSAutoreleasePool pool;

	CmnResult localResult;
	GpuResult localGpuResult;

	Mtl4AllocationMetadata* allocation = mtl4AcquireAllocationMetadataFromGpuPtr(ptrGpu, true);
	if (allocation == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return 0;
	}
	defer (mtl4ReleaseAllocationMetadata());

	size_t offsetFromBase = mtl4GpuPtrOffsetFromBase(allocation, ptrGpu);
	
	MTLTextureDescriptor* textureDescriptor = mtl4GpuTextureDescToMtl(
		desc,
		gMtl4ResourceOptionsFor[allocation->memory]
	);

	id<MTLTexture> texture = [allocation->backing
		newTextureWithDescriptor:textureDescriptor
		offset:offsetFromBase];
	if (texture == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return {};
	}

	Mtl4TextureMetadata metadata = {};
	metadata.texture = texture;
	metadata.descriptor = *desc;

	CmnScopedStorageSyncLockWrite guard(&gMtl4TextureStorage.sync);

	Mtl4Texture handle = cmnInsert(&gMtl4TextureStorage.textures, metadata, &localResult);
	if (localResult != CMN_SUCCESS) {
		[texture release];

		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return {};
	}

	mtl4AssociateTextureToAllocation(allocation, handle, &localGpuResult);
	if (localGpuResult != GPU_SUCCESS) {
		cmnRemove(&gMtl4TextureStorage.textures, handle);
		[texture release];

		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return {};
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return mtl4HandleToGpuTexture(handle);
}

GpuTextureSizeAlign mtl4TextureSizeAlign(const GpuTextureDesc* desc, GpuResult* result) {
	CmnScopedNSAutoreleasePool pool;

	(void)result;

	MTLTextureDescriptor* textureDescriptor = mtl4GpuTextureDescToMtl(
		desc,
		MTLResourceStorageModePrivate
	);

	MTLSizeAndAlign sizeNAlign = [gMtl4Context.device heapTextureSizeAndAlignWithDescriptor:textureDescriptor];

	return {
		/*size=*/	sizeNAlign.size,
		/*align=*/	sizeNAlign.align,
	};
}

Mtl4TextureMetadata* mtl4AcquireTextureMetadataFrom(Mtl4Texture texture) {
	bool wasHandleValid;
	Mtl4TextureMetadata* metadata = cmnStorageSyncAcquireResource(
		&gMtl4TextureStorage.textures,
		&gMtl4TextureStorage.sync,
		texture,
		&wasHandleValid
	);
	if (!wasHandleValid) {
		return nullptr;
	}

	return metadata;
}

void mtl4ReleaseTextureMetadata(void) {
	cmnStorageSyncReleaseResource(&gMtl4TextureStorage.sync);
}

GpuTextureDescriptor mtl4TextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result) {
	CmnScopedNSAutoreleasePool pool;

	GpuResult localResult;

	Mtl4Texture handle = mtl4GpuTextureToHadle(texture);

	Mtl4TextureMetadata* metadata = mtl4AcquireTextureMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_TEXTURE_FOUND);
		return {};
	}
	defer (mtl4ReleaseTextureMetadata());

	bool didFindView;
	id<MTLTexture> view = cmnGet(&metadata->relatedViews, *desc, &didFindView);

	if (didFindView) {
		MTLResourceID resourceId = [view gpuResourceID];

		CMN_SET_RESULT(result, GPU_SUCCESS);
		return mtl4TextureResourceIdToDescriptor(resourceId);
	} else {
		MTLTextureViewDescriptor* viewDescriptor = mtl4GpuViewDescToMtl(metadata->texture, desc);

		id<MTLTexture> view = [metadata->texture newTextureViewWithDescriptor:viewDescriptor];
		if (view == nil) {
			[viewDescriptor release];
			CMN_SET_RESULT(result, GPU_GENERAL_ERROR);
			return {};
		}

		MTLResourceID resourceId = [view gpuResourceID];

		mtl4AssociateViewToTexture(metadata, view, desc, &localResult);
		if (localResult != GPU_SUCCESS) {
			[viewDescriptor release];
			[view release];

			CMN_SET_RESULT(result, localResult);
			return {};
		}

		[viewDescriptor release];
		CMN_SET_RESULT(result, GPU_SUCCESS);
		return mtl4TextureResourceIdToDescriptor(resourceId);
	}
}

GpuTextureDescriptor mtl4RWTextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result) {
	CmnScopedNSAutoreleasePool pool;

	return mtl4TextureViewDescriptor(texture, desc, result);
}

void mtl4FreeTexture(Mtl4Texture texture) {
	CmnScopedNSAutoreleasePool pool;

	Mtl4TextureMetadata* metadata = mtl4AcquireTextureMetadataFrom(texture);
	if (metadata == nullptr) {
		return;
	}
	defer (mtl4ReleaseTextureMetadata());

	cmnAtomicStore(&metadata->scheduledForDeletion, true);
	mtl4ScheduleTextureForDeletion(texture);
}

bool mtl4IsTextureScheduledForDeletion(Mtl4Texture texture) {
	Mtl4TextureMetadata* metadata = mtl4AcquireTextureMetadataFrom(texture);
	if (metadata == nullptr) {
		return false;
	}
	defer (mtl4ReleaseTextureMetadata());
	
	return cmnAtomicLoad(&metadata->scheduledForDeletion);
}

MTLTextureDescriptor* mtl4GpuTextureDescToMtl(const GpuTextureDesc* desc, MTLResourceOptions resourceOptions) {
	MTLTextureDescriptor* textureDescriptor = [[MTLTextureDescriptor new] autorelease];

	textureDescriptor.textureType		= gMtl4GpuToMtlTextureType[desc->type];
	textureDescriptor.pixelFormat		= gMtl4GpuToMtlFormat[desc->format];
	textureDescriptor.width			= desc->dimensions[0];
	textureDescriptor.height		= (desc->type == GPU_TEXTURE_1D) ? 1 : desc->dimensions[1];
	textureDescriptor.mipmapLevelCount 	= desc->mipCount;
	textureDescriptor.sampleCount		= desc->sampleCount;
	textureDescriptor.resourceOptions 	= resourceOptions;
	textureDescriptor.usage			= gMtl4GpuToMtlUsage[desc->usage];
	// TODO: Maybe not always true.
	textureDescriptor.allowGPUOptimizedContents = true;
	// TODO: Some formats should be compressed
	textureDescriptor.compressionType 	= MTLTextureCompressionTypeLossless;
	textureDescriptor.swizzle 		= MTLTextureSwizzleChannelsDefault;
	textureDescriptor.placementSparsePageSize = (MTLSparsePageSize)0;

	if (desc->type == GPU_TEXTURE_3D) {
		textureDescriptor.depth	= desc->dimensions[2];
	} else {
		textureDescriptor.depth	= 1;
	}

	if (desc->type == GPU_TEXTURE_2D_ARRAY || desc->type == GPU_TEXTURE_CUBE_ARRAY) {
		textureDescriptor.arrayLength	= desc->layerCount;
	} else {
		textureDescriptor.arrayLength	= 1;
	}

	return textureDescriptor;
}

MTLTextureViewDescriptor* mtl4GpuViewDescToMtl(id<MTLTexture> referenceTexture, const GpuViewDesc* desc) {
	MTLTextureViewDescriptor* viewDescriptor = [MTLTextureViewDescriptor new];

	viewDescriptor.pixelFormat	= gMtl4GpuToMtlFormat[desc->format];
	viewDescriptor.textureType	= referenceTexture.textureType;
	viewDescriptor.levelRange	= NSMakeRange(desc->baseMip, desc->mipCount);
	viewDescriptor.sliceRange	= NSMakeRange(desc->baseLayer, desc->layerCount);
	viewDescriptor.swizzle		= MTLTextureSwizzleChannelsDefault;

	return viewDescriptor;
}

void mtl4AssociateViewToTexture(Mtl4TextureMetadata* metadata, id<MTLTexture> view, const GpuViewDesc* desc, GpuResult* result) {
	CmnResult localResult;

	CmnAllocator poolAllocator = cmnPoolAllocator(&gMtl4TextureStorage.textureViewsPool);

	cmnInsert(&metadata->relatedViews, *desc, view, poolAllocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_SUCCESS);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4FreeAssociatedTextureViews(Mtl4TextureMetadata* metadata) {
	CmnKeyedChainIterator<GpuViewDesc, id<MTLTexture>, 8> iter;
	cmnCreateKeyedChainIterator(&metadata->relatedViews, &iter);

	GpuViewDesc* key;
	id<MTLTexture>* value;
	while (cmnIterate(&iter, &key, &value)) {
		[*value release];
	}

	CmnAllocator poolAllocator = cmnPoolAllocator(&gMtl4TextureStorage.textureViewsPool);
	cmnDestroyKeyedChain(&metadata->relatedViews, poolAllocator);
}

void mtl4DestroyTexture(Mtl4Texture texture) {
	bool wasHandleValid;
	Mtl4TextureMetadata* metadata = &cmnGet(&gMtl4TextureStorage.textures, texture, &wasHandleValid);
	if (!wasHandleValid) {
		return;
	}

	if (!metadata->scheduledForDeletion) {
		return;
	}

	mtl4FreeAssociatedTextureViews(metadata);
	[metadata->texture release];

	cmnRemove(&gMtl4TextureStorage.textures, texture);
}

