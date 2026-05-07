#include "textures.h"

#include <lib/common/memory.h>
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
		goto on_error_cleanup;
	}

	gMtl4TextureStorage.textureViewsPage = cmnCreatePage(4 * 1024 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		goto on_error_cleanup;
	}

	gMtl4TextureStorage.textureMedatadaArena = cmnPageToArena(gMtl4TextureStorage.textureMetadataPage);
	gMtl4TextureStorage.textureViewsPool = cmnPageToPool(gMtl4TextureStorage.textureViewsPage, 192);

	CmnAllocator allocator;
	allocator = cmnArenaAllocator(&gMtl4TextureStorage.textureMedatadaArena);

	cmnCreateHandleMap(&gMtl4TextureStorage.textures, allocator, {}, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		goto on_error_cleanup;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;

on_error_cleanup:
	mtl4FiniTextureStorage();
}

void mtl4FiniTextureStorage(void) {
	cmnDestroyPage(gMtl4TextureStorage.textureMetadataPage);
	cmnDestroyPage(gMtl4TextureStorage.textureViewsPage);

	gMtl4TextureStorage = {};
}

GpuTexture mtl4CreateTexture(const GpuTextureDesc* desc, void* ptrGpu, GpuResult* result) {
	CmnResult localResult;
	GpuResult localGpuResult;

	size_t offsetFromBase = mtl4GpuAddressOffsetFromBase(ptrGpu);

	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFromGpuPtr(ptrGpu);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return 0;
	}
	defer (mtl4ReleaseAllocationMetadata());
	
	MTLTextureDescriptor* textureDescriptor = mtl4GpuTextureDescToMtl(
		desc,
		MTLResourceStorageModePrivate
	);
	defer ([textureDescriptor release]);

	id<MTLTexture> texture;
	id<MTLHeap> backingHeap = cmnAtomicLoad(&metadata->associatedTextureHeap);

	if (backingHeap == nil) {
		GpuTextureSizeAlign expectedSizeAlign = mtl4TextureSizeAlign(desc, nullptr);

		if (
			!cmnIsAlignedTo((uintptr_t)ptrGpu, expectedSizeAlign.align) ||
			(metadata->size - offsetFromBase) < expectedSizeAlign.size
		) {
			CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
			return 0;
		}

		// The buffer must contain a new heap, for multiple textures
		MTLHeapDescriptor* heapDescriptor = [MTLHeapDescriptor new];
		defer ([heapDescriptor release]);

		// heapDescriptor.resourceOptions = MTLResourceStorageModePrivate | MTLResourceHazardTrackingModeUntracked;
		heapDescriptor.resourceOptions = MTLResourceStorageModePrivate;
		heapDescriptor.size = metadata->size;

		backingHeap = [gMtl4Context.device newHeapWithDescriptor:heapDescriptor];
		if (backingHeap == nil) {
			CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
			return 0;
		}

		// NOTE: Another thread may have got here before us. If so, let's use the heap set by the other
		//	thread.
		if (!cmnAtomicCompareExchangeStrong(&metadata->associatedTextureHeap, (id<MTLHeap>)nil, backingHeap)) {
			[backingHeap release];
			backingHeap = cmnAtomicLoad(&metadata->associatedTextureHeap);
		}

		mtl4AddAllocationToResidencySet(backingHeap);

		texture = [backingHeap newTextureWithDescriptor:textureDescriptor];
		if (texture == nil) {
			[backingHeap release];

			CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
			return 0;
		}

		cmnAtomicOr(&metadata->internalUsage, (Mtl4InternalAllocationUsages)MTL4_ALLOCATION_FOR_TEXTURE_HEAP);

	} else {
		texture = [backingHeap newTextureWithDescriptor:textureDescriptor];
		if (texture == nil) {
			CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
			return 0;
		}
	}

	Mtl4TextureMetadata textureMetadata = {};
	textureMetadata.texture = texture;
	memcpy(&textureMetadata.descriptor, desc, sizeof(GpuTextureDesc));

	Mtl4Texture textureHandle;
	{
		CmnScopedStorageSyncLockWrite guard(&gMtl4TextureStorage.sync);

		textureHandle = cmnInsert(&gMtl4TextureStorage.textures, textureMetadata, &localResult);
		if (localResult != CMN_SUCCESS) {
			[texture release];

			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return 0;
		}
	}

	mtl4AssociateTextureToAllocation(metadata, textureHandle, &localGpuResult);
	if (localGpuResult != GPU_SUCCESS) {
		[texture release];
		{
			CmnScopedStorageSyncLockWrite guard(&gMtl4TextureStorage.sync);
			cmnRemove(&gMtl4TextureStorage.textures, textureHandle);
		}
		
		CMN_SET_RESULT(result, localGpuResult);
		return 0;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return mtl4HandleToGpuTexture(textureHandle);
}

GpuTextureSizeAlign mtl4TextureSizeAlign(const GpuTextureDesc* desc, GpuResult* result) {
	(void)result;

	MTLTextureDescriptor* textureDescriptor = mtl4GpuTextureDescToMtl(
		desc,
		// MTLResourceStorageModePrivate | MTLResourceHazardTrackingModeUntracked
		MTLResourceStorageModePrivate
	);

	MTLSizeAndAlign sizeNAlign = [gMtl4Context.device heapTextureSizeAndAlignWithDescriptor:textureDescriptor];

	[textureDescriptor release];
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
	return mtl4TextureViewDescriptor(texture, desc, result);
}

void mtl4FreeTexture(Mtl4Texture texture) {
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
	MTLTextureDescriptor* textureDescriptor = [MTLTextureDescriptor new];

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

