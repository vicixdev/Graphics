#include "allocation.h"

#include <lib/common/heap_allocator.h>
#include <lib/metal4/context.h>
#include <lib/metal4/deletion_manager.h>

Mtl4AllocationStorage gMtl4AllocationStorage;

static MTLResourceOptions gMtl4ResourceOptionsFor[] = {
	/*GPU_MEMORY_DEFAULT=*/		MTLResourceStorageModeShared |  MTLResourceCPUCacheModeWriteCombined,
	/*GPU_MEMORY_GPU=*/		MTLResourceStorageModePrivate,
	/*GPU_MEMORY_READBACK=*/	MTLResourceStorageModeShared | MTLResourceCPUCacheModeDefaultCache,
};

void mtl4InitAllocationStorage(GpuResult* result) {
	CmnResult localResult;

	CmnAllocator addressRangeMapNodesAllocator;
	CmnAllocator miscArenaAllocator;

	// Preallocate for more than 512k buffers
	gMtl4AllocationStorage.miscPoolPage = cmnCreatePage(32 * 1024 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	// Preallocate for more than 512k buffers
	gMtl4AllocationStorage.miscArenaPage = cmnCreatePage(32 * 1024 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	// Preallocate for more than 512k buffers
	gMtl4AllocationStorage.addressRangeMapPage = cmnCreatePage(16 * 1024 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	gMtl4AllocationStorage.miscPool = cmnPageToPool(
		gMtl4AllocationStorage.miscPoolPage,
		MTL4_ALLOCATION_METADATA_OBJECT_SIZE);
	gMtl4AllocationStorage.miscArena = cmnPageToArena(gMtl4AllocationStorage.miscArenaPage);
	gMtl4AllocationStorage.addressRangeMapNodesPool = cmnPageToPool(
		gMtl4AllocationStorage.addressRangeMapPage,
		sizeof(CmnBTreeNode<Mtl4AddressRange, Mtl4AllocationMetadata*>));

	addressRangeMapNodesAllocator	= cmnPoolAllocator(&gMtl4AllocationStorage.addressRangeMapNodesPool);
	miscArenaAllocator		= cmnArenaAllocator(&gMtl4AllocationStorage.miscArena);

	cmnCreateBTree(
		&gMtl4AllocationStorage.cpuAddressRangeMap,
		{},
		addressRangeMapNodesAllocator,
		&localResult
	);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	cmnCreatePointerMap(&gMtl4AllocationStorage.cpuAllocationMap, 1024, {}, cmnHeapAllocator(), &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	cmnCreateElementPool(&gMtl4AllocationStorage.gpuAllocationMap, miscArenaAllocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	cmnCreateHandleMap(&gMtl4AllocationStorage.allocations, miscArenaAllocator, {}, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4FiniAllocationStorage(void) {
	cmnDestroyPage(gMtl4AllocationStorage.miscPoolPage		);
	cmnDestroyPage(gMtl4AllocationStorage.addressRangeMapPage	);
	cmnDestroyPage(gMtl4AllocationStorage.miscArenaPage		);

	cmnDestroyPointerMap(&gMtl4AllocationStorage.cpuAllocationMap	);
	
	gMtl4AllocationStorage = {};
}

id<MTLBuffer> mtl4AllocateBuffer(size_t size, size_t align, GpuMemory memory, GpuResult* result) {
	(void)align;

	MTLResourceOptions resourceOptions = gMtl4ResourceOptionsFor[memory];

	// TODO: Overallocate to ensure alignment
	id<MTLBuffer> buffer = [gMtl4Context.device
		newBufferWithLength:size
		options: resourceOptions
	];
	if (buffer == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return nil;
	}

	[gMtl4AllocationStorage.residencySet addAllocation:buffer];

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return buffer;
}

void* mtl4MallocDirectMemory(size_t size, size_t align, GpuMemory memory, GpuResult* result) {
	CmnResult localResult;
	GpuResult localGpuResult;

	Mtl4AllocationMetadata metadata = {};
	Mtl4AddressRange cpuRange	= {};
	void* cpuAddress		= nullptr;
	size_t gpuAllocationIndex	= 0;
	Mtl4AllocationHandle handle	= {};

	id<MTLBuffer> buffer = mtl4AllocateBuffer(size, align, memory, &localGpuResult);
	if (localGpuResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localGpuResult);
		return nullptr;
	}

	cpuAddress = [buffer contents];
	assert(mtl4IsCpuAddress(cpuAddress));

	cpuRange.start	= (uintptr_t)cpuAddress;
	cpuRange.length	= size;

	{
		CmnScopedStorageSyncLockWrite guard(&gMtl4AllocationStorage.sync);

		gpuAllocationIndex = cmnInsert(&gMtl4AllocationStorage.gpuAllocationMap, {}, &localResult);
		if (localResult != CMN_SUCCESS) {
			[buffer release];

			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return nullptr;
		}

		metadata.buffer		= buffer;
		metadata.size		= size;
		metadata.align		= align;
		metadata.memory		= memory;
		metadata.assignedGpuAddress.guard	= 1;
		metadata.assignedGpuAddress.offset	= 0;
		metadata.assignedGpuAddress.allocationIdentifier = gpuAllocationIndex;
		metadata.internalUsage =
			MTL4_ALLOCATION_DIRECT |
			MTL4_ALLOCATION_CPU_ACCESSIBLE |
			MTL4_ALLOCATION_COMMITTED;

		handle = cmnInsert(&gMtl4AllocationStorage.allocations, metadata, &localResult);
		if (localResult != CMN_SUCCESS) {
			[buffer release];
			cmnRemove(&gMtl4AllocationStorage.gpuAllocationMap, gpuAllocationIndex);

			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return nullptr;
		}
		gMtl4AllocationStorage.gpuAllocationMap[gpuAllocationIndex] = handle;

		cmnInsert(&gMtl4AllocationStorage.cpuAddressRangeMap, cpuRange, handle, &localResult);
		if (localResult != CMN_SUCCESS) {
			[buffer release];
			cmnRemove(&gMtl4AllocationStorage.gpuAllocationMap, gpuAllocationIndex);
			cmnRemove(&gMtl4AllocationStorage.allocations, handle);

			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return nullptr;
		}

		cmnInsert(&gMtl4AllocationStorage.cpuAllocationMap, (uintptr_t)cpuAddress, handle, &localResult);
		if (localResult != CMN_SUCCESS) {
			[buffer release];
			cmnRemove(&gMtl4AllocationStorage.gpuAllocationMap, gpuAllocationIndex);
			cmnRemove(&gMtl4AllocationStorage.allocations, handle);
			cmnRemove(&gMtl4AllocationStorage.cpuAddressRangeMap, cpuRange);

			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return nullptr;
		}
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return cpuAddress;
}

void* mtl4MallocVirtualMemory(size_t size, size_t align, GpuResult* result) {
	(void)align;
	CmnResult localResult;

	Mtl4AllocationMetadata metadata = {};
	Mtl4AllocationHandle handle = {};

	Mtl4GpuAddress address;
	{
		CmnScopedStorageSyncLockWrite guard(&gMtl4AllocationStorage.sync);

		size_t metadataIndex = cmnInsert(&gMtl4AllocationStorage.gpuAllocationMap, {}, &localResult);
		if (localResult != CMN_SUCCESS) {
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return nullptr;
		}

		metadata.buffer		= nil;
		metadata.size		= size;
		metadata.align		= align;
		metadata.memory		= GPU_MEMORY_GPU;
		address.allocationIdentifier	= metadataIndex;
		address.guard			= true;
		address.offset			= 0;
		metadata.assignedGpuAddress	= address;
		metadata.internalUsage	= MTL4_ALLOCATION_VIRTUAL;

		handle = cmnInsert(&gMtl4AllocationStorage.allocations, metadata, &localResult);
		if (localResult != CMN_SUCCESS) {
			cmnRemove(&gMtl4AllocationStorage.gpuAllocationMap, metadataIndex);

			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return nullptr;
		}

		gMtl4AllocationStorage.gpuAllocationMap[metadataIndex] = handle;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return mtl4GpuAddressToPtr(address);
}

void* mtl4Malloc(size_t size, size_t align, GpuMemory memory, GpuResult* result) {
	switch (memory) {
		case GPU_MEMORY_DEFAULT:
		case GPU_MEMORY_READBACK: {
			return mtl4MallocDirectMemory(size, align, memory, result);
		}
		case GPU_MEMORY_GPU: {
			return mtl4MallocVirtualMemory(size, align, result);
		}
	}

	return nullptr;
}

void mtl4Free(void* ptr) {
	if (ptr == nullptr) {
		return;
	}

	bool couldFindMetadata;
	Mtl4AllocationHandle handle = mtl4AllocationHandleOf(ptr, false, &couldFindMetadata);
	if (!couldFindMetadata) {
		return;
	}

	{
		Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFrom(handle, nullptr);
		if (metadata == nullptr) {
			return;
		}
		defer (mtl4ReleaseAllocationMetadata());

		cmnAtomicOr(&metadata->internalUsage, (Mtl4InternalAllocationUsages)MTL4_ALLOCATION_SCHEDULED_FOR_DELETION);

		// NOTE: May as well...
		mtl4FreeAssociatedTextures(metadata);

		mtl4ScheduleAllocationForDeletion(handle);
	}

	mtl4CheckForResourceDeletion();
}

Mtl4AllocationMetadata* mtl4AcquireAllocationMetadataFrom(Mtl4AllocationHandle handle, bool* wasHandleValid) {
	return cmnStorageSyncAcquireResource(
		&gMtl4AllocationStorage.allocations,
		&gMtl4AllocationStorage.sync,
		handle,
		wasHandleValid
	);
}

void mtl4ReleaseAllocationMetadata(void) {
	cmnStorageSyncReleaseResource(&gMtl4AllocationStorage.sync);
}

uintptr_t mtl4GpuAddressToActual(void* gpuPtr, bool* couldFindMetadata) {
	Mtl4GpuAddress address = mtl4PtrToGpuAddress(gpuPtr);

	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFromGpuPtr(gpuPtr);
	if (metadata == nullptr) {
		CMN_SET_NULLABLE(couldFindMetadata, false);
		return 0;
	}
	defer (mtl4ReleaseAllocationMetadata());

	if (metadata->buffer == nil) {
		CMN_SET_NULLABLE(couldFindMetadata, false);
		return 0;
	}

	return metadata->buffer.gpuAddress + address.offset;
}

Mtl4AllocationHandle mtl4AllocationHandleOf(void* ptr, bool attemptRangeBasedLookup, bool* couldFindMetadata) {
	if (mtl4IsCpuAddress(ptr)) {
		return mtl4AllocationHandleOfCpuPtr(ptr, attemptRangeBasedLookup, couldFindMetadata);
	} else {
		return mtl4AllocationHandleOfGpuPtr(ptr, couldFindMetadata);
	}

	return {};
}

Mtl4AllocationHandle mtl4AllocationHandleOfCpuPtr(void* ptr, bool attemptRangeBasedLookup, bool* couldFindMetadata) {
	assert(mtl4IsCpuAddress(ptr));

	CmnScopedStorageSyncLockRead guard(&gMtl4AllocationStorage.sync);

	bool didFindElement;
	Mtl4AllocationHandle handle;

	// NOTE: Attempt fast lookup. Will find the address if no offset has beed applied to the pointer.
	handle = cmnGet(&gMtl4AllocationStorage.cpuAllocationMap, (uintptr_t)ptr, &didFindElement);
	if (didFindElement) {
		CMN_SET_NULLABLE(couldFindMetadata, true);
		return handle;
	}

	if (!attemptRangeBasedLookup) {
		CMN_SET_NULLABLE(couldFindMetadata, false);
		return {};
	}
	
	// NOTE: Slow lookup
	Mtl4AddressRange range;
	range.start = (uintptr_t)ptr;
	range.length = 0;

	handle = cmnGet(&gMtl4AllocationStorage.cpuAddressRangeMap, range, &didFindElement);
	if (didFindElement) {
		CMN_SET_NULLABLE(couldFindMetadata, true);
		return handle;
	}

	CMN_SET_NULLABLE(couldFindMetadata, false);
	return {};
}

Mtl4AllocationHandle mtl4AllocationHandleOfGpuPtr(Mtl4GpuAddress address, bool* couldFindMetadata) {
	if (address.guard == 0) {
		CMN_SET_NULLABLE(couldFindMetadata, false);
		return {};
	}

	CmnScopedStorageSyncLockRead guard(&gMtl4AllocationStorage.sync);

	CMN_SET_NULLABLE(couldFindMetadata, true);
	return gMtl4AllocationStorage.gpuAllocationMap[address.allocationIdentifier];
}

Mtl4AllocationMetadata* mtl4AcquireAllocationMetadataFrom(void* ptr, bool attemptRangeBasedLookup) {
	bool couldFindMetadata;
	Mtl4AllocationHandle handle = mtl4AllocationHandleOf(ptr, attemptRangeBasedLookup, &couldFindMetadata);
	if (!couldFindMetadata) {
		return nullptr;
	}

	bool wasHandleValid;
	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFrom(handle, &wasHandleValid);
	if (!wasHandleValid) {
		return nullptr;
	}

	return metadata;
}

Mtl4AllocationMetadata* mtl4AcquireAllocationMetadataFromCpuPtr(void* ptr, bool attemptRangeBasedLookup) {
	bool couldFindMetadata;
	Mtl4AllocationHandle handle = mtl4AllocationHandleOfCpuPtr(ptr, attemptRangeBasedLookup, &couldFindMetadata);
	if (!couldFindMetadata) {
		return nullptr;
	}

	bool wasHandleValid;
	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFrom(handle, &wasHandleValid);
	if (!wasHandleValid) {
		return nullptr;
	}

	return metadata;
}

Mtl4AllocationMetadata* mtl4AcquireAllocationMetadataFromGpuPtr(Mtl4GpuAddress address) {
	bool couldFindMetadata;
	Mtl4AllocationHandle handle = mtl4AllocationHandleOfGpuPtr(address, &couldFindMetadata);
	if (!couldFindMetadata) {
		return nullptr;
	}

	bool wasHandleValid;
	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFrom(handle, &wasHandleValid);
	if (!wasHandleValid) {
		return nullptr;
	}

	return metadata;
}

void* mtl4HostToDevicePointer(void* ptr, GpuResult* result) {
	if (mtl4IsGpuAddress(ptr)) {
		CMN_SET_RESULT(result, GPU_ALLOCATION_MEMORY_IS_GPU);
		return nullptr;
	}

	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFrom(ptr, true);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return nullptr;
	}
	defer (mtl4ReleaseAllocationMetadata());

	CMN_SET_RESULT(result, GPU_SUCCESS);

	uintptr_t baseAddress = (uintptr_t)mtl4CpuAddressOf(metadata);
	uintptr_t offsetFromBase = (uintptr_t)ptr - baseAddress;

	Mtl4GpuAddress address = metadata->assignedGpuAddress;
	address.offset = offsetFromBase;
	return mtl4GpuAddressToPtr(address);
}

void mtl4AssociateTextureToAllocation(Mtl4AllocationMetadata* metadata, Mtl4Texture texture, GpuResult* result) {
	CmnResult localResult;

	cmnInsert(&metadata->relatedTextures, texture, cmnPoolAllocator(&gMtl4AllocationStorage.miscPool), &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4FreeAssociatedTextures(Mtl4AllocationMetadata* metadata) {
	CmnScopedWriteRWMutex guard(&metadata->relatedTextures.mutex);

	CmnChainIterator<Mtl4Texture, 10> iter;
	cmnCreateChainIterator(&metadata->relatedTextures, &iter);

	Mtl4Texture* texture;
	while (cmnIterate(&iter, &texture)) {
		mtl4FreeTexture(*texture);
	}

	cmnDestroyChain(&metadata->relatedTextures, cmnPoolAllocator(&gMtl4AllocationStorage.miscPool));
}

void mtl4EnsureBackingBufferIsAllocated(Mtl4AllocationMetadata* metadata, GpuResult* result) {
	GpuResult localResult;

	if (cmnAtomicLoad(&metadata->buffer) != nil) {
		CMN_SET_RESULT(result, GPU_SUCCESS);
		return;
	}

	id<MTLBuffer> buffer = mtl4AllocateBuffer(metadata->size, metadata->align, metadata->memory, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}

	// NOTE: Another thread could have set this up before us. If so, let's use the other thread buffer.
	if (!cmnAtomicCompareExchangeStrong(&metadata->buffer, (id<MTLBuffer>)nil, buffer)) {
		[gMtl4AllocationStorage.residencySet removeAllocation:buffer];
		[buffer release];
	}

	cmnAtomicOr(&metadata->internalUsage, (Mtl4InternalAllocationUsages)MTL4_ALLOCATION_COMMITTED);

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4EnsureBackingBufferIsAllocated(Mtl4GpuAddress address, GpuResult* result) {
	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFromGpuPtr(address);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_SUCCESS);
		return;
	}
	defer (mtl4ReleaseAllocationMetadata());

	mtl4EnsureBackingBufferIsAllocated(metadata, result);
}

void mtl4MarkAsContainingSignals(Mtl4AllocationMetadata* metadata, GpuResult* result) {
	GpuResult localResult;

	Mtl4InternalAllocationUsages usages = cmnAtomicLoad(&metadata->internalUsage);

	if (usages & MTL4_ALLOCATION_CPU_ACCESSIBLE) {
		cmnAtomicOr(&metadata->internalUsage, (Mtl4InternalAllocationUsages)MTL4_ALLOCATION_CONTAINS_SIGNALS);
	} else if (!(usages & MTL4_ALLOCATION_COMMITTED)) {
		id<MTLBuffer> buffer = mtl4AllocateBuffer(metadata->size, metadata->align, metadata->memory, &localResult);
		if (localResult != GPU_SUCCESS) {
			CMN_SET_RESULT(result, localResult);
			return;
		}

		// NOTE: Another thread could have set this up before us. If so, let's use the other thread buffer.
		if (!cmnAtomicCompareExchangeStrong(&metadata->buffer, (id<MTLBuffer>)nil, buffer)) {
			[buffer release];
		}

		cmnAtomicOr(
			&metadata->internalUsage,
			(Mtl4InternalAllocationUsages)MTL4_ALLOCATION_COMMITTED | MTL4_ALLOCATION_CPU_ACCESSIBLE);

		CMN_SET_RESULT(result, GPU_SUCCESS);
	}
}

bool mtl4IsAllocationScheduledForDeletion(void* ptr) {
	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFrom(ptr, true);
	if (metadata == nullptr) {
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	return cmnAtomicLoad(&metadata->internalUsage) & MTL4_ALLOCATION_SCHEDULED_FOR_DELETION;
}

void mtl4DestroyAllocation(Mtl4AllocationHandle handle) {
	bool wasHandleValid;
	Mtl4AllocationMetadata* metadata = &cmnGet(&gMtl4AllocationStorage.allocations, handle, &wasHandleValid);
	if (!wasHandleValid) {
		return;
	}

	if (!(metadata->internalUsage & MTL4_ALLOCATION_SCHEDULED_FOR_DELETION)) {
		return;
	}

	void* ptr = [metadata->buffer contents];

	Mtl4AddressRange range;
	range.start = (uintptr_t)ptr;
	range.length = 0;

	mtl4FreeAssociatedTextures(metadata);

	[gMtl4AllocationStorage.residencySet removeAllocation:metadata->buffer];

	if (metadata->buffer != nil) {
		[metadata->buffer release];
	}

	[gMtl4AllocationStorage.residencySet removeAllocation:metadata->associatedTextureHeap];
	[metadata->associatedTextureHeap release];

	cmnRemove(&gMtl4AllocationStorage.cpuAddressRangeMap, range);
	cmnRemove(&gMtl4AllocationStorage.cpuAllocationMap, (uintptr_t)ptr);
	cmnRemove(&gMtl4AllocationStorage.gpuAllocationMap, metadata->assignedGpuAddress.allocationIdentifier);
	cmnRemove(&gMtl4AllocationStorage.allocations, handle);
}
