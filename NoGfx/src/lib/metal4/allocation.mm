#include "allocation.h"

#include <lib/common/heap_allocator.h>
#include <lib/common/scoped_nsautoreleasepool.h>
#include <lib/metal4/context.h>
#include <lib/metal4/tables.h>
#include <lib/metal4/deletion_manager.h>

Mtl4AllocationStorage gMtl4AllocationStorage;

void mtl4InitAllocationStorage(GpuResult* result) {
	CmnResult localResult;

	gMtl4AllocationStorage.arenaPage = cmnCreatePage(32 * 1024 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	gMtl4AllocationStorage.miscPoolPage = cmnCreatePage(32 * 1024 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	gMtl4AllocationStorage.nodesPoolPage = cmnCreatePage(32 * 1024 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	gMtl4AllocationStorage.arena = cmnPageToArena(gMtl4AllocationStorage.arenaPage);
	gMtl4AllocationStorage.miscPool = cmnPageToPool(
		gMtl4AllocationStorage.miscPoolPage,
		MTL4_ALLOCATIONS_MISCPOOLSLOT_SIZE);
	gMtl4AllocationStorage.nodesPool = cmnPageToPool(
		gMtl4AllocationStorage.nodesPoolPage,
		MTL4_ALLOCATIONS_NODESPOLLSLOT_SIZE);

	CmnAllocator nodesAllocator = cmnPoolAllocator(&gMtl4AllocationStorage.nodesPool);
	CmnAllocator arenaAllocator = cmnArenaAllocator(&gMtl4AllocationStorage.arena);

	cmnCreatePointerMap(&gMtl4AllocationStorage.cpuDirectLookup, 1024, {}, cmnHeapAllocator(), &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	cmnCreatePointerMap(&gMtl4AllocationStorage.gpuDirectLookup, 1024, {}, cmnHeapAllocator(), &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	cmnCreateBTree(
		&gMtl4AllocationStorage.cpuRangeLookup,
		{},
		nodesAllocator,
		&localResult
	);
	assert(localResult == CMN_SUCCESS && "The tree creation should not fail.");

	cmnCreateBTree(
		&gMtl4AllocationStorage.gpuRangeLookup,
		{},
		nodesAllocator,
		&localResult
	);
	assert(localResult == CMN_SUCCESS && "The tree creation should not fail.");

	cmnCreateHandleMap(&gMtl4AllocationStorage.allocations, arenaAllocator, {}, &localResult);
	assert(localResult == CMN_SUCCESS && "The handle map creation should not fail.");

	cmnCreateExponentialArray(&gMtl4AllocationStorage.defaultSmallAllocations, arenaAllocator, &localResult);
	assert(localResult == CMN_SUCCESS && "The exponental array creation should not fail.");

	cmnCreateExponentialArray(&gMtl4AllocationStorage.privateSmallAllocations, arenaAllocator, &localResult);
	assert(localResult == CMN_SUCCESS && "The exponental array creation should not fail.");

	cmnCreateExponentialArray(&gMtl4AllocationStorage.readbackSmallAllocations, arenaAllocator, &localResult);
	assert(localResult == CMN_SUCCESS && "The exponental array creation should not fail.");

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4FiniAllocationStorage(void) {
	CmnHandleMapIterator<Mtl4AllocationMetadata> iter;
	cmnCreateHandleMapIterator(&gMtl4AllocationStorage.allocations, &iter);

	Mtl4AllocationMetadata* allocation;
	while (cmnIterate(&iter, &allocation)) {
		[allocation->backing release];
		[allocation->buffer release];
	}

	cmnDestroyPage(gMtl4AllocationStorage.miscPoolPage);
	cmnDestroyPage(gMtl4AllocationStorage.nodesPoolPage);
	cmnDestroyPage(gMtl4AllocationStorage.arenaPage);

	cmnDestroyPointerMap(&gMtl4AllocationStorage.cpuDirectLookup);
	cmnDestroyPointerMap(&gMtl4AllocationStorage.gpuDirectLookup);

	gMtl4AllocationStorage = {};
}

void mtl4BigAllocate(Mtl4AllocationMetadata* metadata, size_t size, size_t align, GpuMemory memory, GpuResult* result) {
	GpuResult localGpuResult = GPU_SUCCESS;

	id<MTLHeap> heap = mtl4AllocateHeap(size, align, memory, &localGpuResult);
	if (localGpuResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localGpuResult);
		return;
	}

	id<MTLBuffer> buffer = [heap
		newBufferWithLength:size
		options:gMtl4ResourceOptionsFor[memory]
		offset:0];
	assert(buffer != nil && "If the heap allocation succeeded, then the buffer allocation should also succeed.");

	metadata->memory	= memory;
	metadata->gpuPtr	= [buffer gpuAddress];
	metadata->size		= size;
	metadata->backing	= heap;
	metadata->buffer	= buffer;

	if (memory != GPU_MEMORY_GPU) {
		metadata->cpuPtr = (uintptr_t)[buffer contents];
	}
}

id<MTLBuffer> mtl4AllocateSmallMemory(
	size_t size,
	size_t align,
	GpuMemory memory,
	Mtl4SmallAllocationMetadata* allocation,
	id<MTLHeap>* heap,
	size_t* offsetInHeap,
	GpuResult* result
) {
	CmnResult localResult;
	GpuResult localGpuResult;

	CmnExponentialArray<Mtl4SmallAllocationStorage>* storages;
	switch (memory) {
		case GPU_MEMORY_DEFAULT: {
			storages = &gMtl4AllocationStorage.defaultSmallAllocations;
			break;
		}
		case GPU_MEMORY_GPU: {
			storages = &gMtl4AllocationStorage.privateSmallAllocations;
			break;
		}
		case GPU_MEMORY_READBACK: {
			storages = &gMtl4AllocationStorage.readbackSmallAllocations;
			break;
		}
	}

	// TODO: Finer locking.
	CmnScopedStorageSyncLockWrite guard(&gMtl4AllocationStorage.sync);

	id<MTLHeap> tlsfHeap;
	TlsfAllocation tlsfAllocation;
	TlsfPool* pool;
	uint32_t offset;

	size_t i = 0;
	for (;;) {
		if (storages->length >= i) {
			mtl4AllocateSmallAllocationStorage(memory, &localGpuResult);
			if (localGpuResult != GPU_SUCCESS) {
				CMN_SET_RESULT(result, localGpuResult);
				return nil;
			}
		}
		Mtl4SmallAllocationStorage* storage = &cmnGet(storages, i);
		
		size_t actualAlign = align;
		if (actualAlign < 256) {
			actualAlign = 256;
		}

		tlsfHeap = storage->heap;
		pool = &storage->pool;
		tlsfAllocation = tlsfAlloc(&storage->pool, size, actualAlign, &offset, &localResult);
		if (localResult == CMN_SUCCESS) {
			break;
		}

		i++;
	}

	id<MTLBuffer> buffer = [tlsfHeap
		newBufferWithLength:size
		options:gMtl4ResourceOptionsFor[memory]
		offset:offset];
	assert(buffer != nil && "If the tlsf allocation succeeded, then the buffer allocation should also succeed.");

	allocation->allocation = tlsfAllocation;
	allocation->pool = pool;
	*offsetInHeap = offset;
	*heap = tlsfHeap;
	CMN_SET_RESULT(result, GPU_SUCCESS);
	return buffer;
}

void mtl4SmallAllocate(Mtl4AllocationMetadata* metadata, size_t size, size_t align, GpuMemory memory, GpuResult* result) {
	GpuResult localResult;

	metadata->buffer = mtl4AllocateSmallMemory(size, align, memory, &metadata->small, &metadata->backing, &metadata->offsetInBacking, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}

	metadata->memory	= memory;
	metadata->gpuPtr	= [metadata->buffer gpuAddress];
	metadata->size		= size;
	metadata->isSmallAllocation = true;

	if (memory != GPU_MEMORY_GPU) {
		metadata->cpuPtr = (uintptr_t)[metadata->buffer contents];
	}
}

void mtl4AllocateSmallAllocationStorage(GpuMemory memory, GpuResult* result) {
	CmnResult localResult;
	GpuResult localGpuResult;

	CmnExponentialArray<Mtl4SmallAllocationStorage>* storages;
	switch (memory) {
		case GPU_MEMORY_DEFAULT: {
			storages = &gMtl4AllocationStorage.defaultSmallAllocations;
			break;
		}
		case GPU_MEMORY_GPU: {
			storages = &gMtl4AllocationStorage.privateSmallAllocations;
			break;
		}
		case GPU_MEMORY_READBACK: {
			storages = &gMtl4AllocationStorage.readbackSmallAllocations;
			break;
		}
	}

	Mtl4SmallAllocationStorage storage = {};

	storage.heap = mtl4AllocateHeap(64 * 1024 * 1024, 0, memory, &localGpuResult);
	if (localGpuResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localGpuResult);
		return;
	}

	tlsfInitPool(&storage.pool, cmnPoolAllocator(&gMtl4AllocationStorage.miscPool), 64 * 1024 * 1024, &localResult);
	if (localResult != CMN_SUCCESS) {
		[storage.heap release];

		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	cmnAppend(storages, storage, &localResult);
	if (localResult != CMN_SUCCESS) {
		[storage.heap release];

		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	mtl4AddAllocationToResidencySet(storage.heap);

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void* mtl4Malloc(size_t size, size_t align, GpuMemory memory, GpuResult* result) {
	CmnScopedNSAutoreleasePool pool;

	CmnResult localResult = CMN_SUCCESS;
	GpuResult localGpuResult = GPU_SUCCESS;
	bool failed = false;

	Mtl4AllocationMetadata metadata = {};
	if (size < MTL4_SMALL_MEMORY_THRESHOLD) {
		mtl4SmallAllocate(&metadata, size, align, memory, &localGpuResult);
		if (localGpuResult != GPU_SUCCESS) {
			CMN_SET_RESULT(result, localGpuResult);
			return nullptr;
		}
	} else {
		mtl4BigAllocate(&metadata, size, align, memory, &localGpuResult);
		if (localGpuResult != GPU_SUCCESS) {
			CMN_SET_RESULT(result, localGpuResult);
			return nullptr;
		}
	}

	defer (if (failed && size >= MTL4_SMALL_MEMORY_THRESHOLD) {
		[metadata.backing release];
		[metadata.buffer release];
	});
	defer (if (failed && size < MTL4_SMALL_MEMORY_THRESHOLD) {
		
	});

	CmnScopedStorageSyncLockWrite guard(&gMtl4AllocationStorage.sync);
	
	Mtl4AllocationHandle handle = cmnInsert(&gMtl4AllocationStorage.allocations, metadata, &localResult);
	if (localResult != CMN_SUCCESS) {
		failed = true;
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return nullptr;
	}
	defer (if (failed) cmnRemove(&gMtl4AllocationStorage.allocations, handle));

	Mtl4AddressRange gpuAddressRange = { /*start=*/metadata.gpuPtr, /*length=*/metadata.size };
	cmnInsert(&gMtl4AllocationStorage.gpuRangeLookup, gpuAddressRange, handle, &localResult);
	if (localResult != CMN_SUCCESS) {
		failed = true;
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return nullptr;
	}
	defer (if (failed) cmnRemove(&gMtl4AllocationStorage.gpuRangeLookup, gpuAddressRange));

	cmnInsert(&gMtl4AllocationStorage.gpuDirectLookup, metadata.gpuPtr, handle, &localResult);
	if (localResult != CMN_SUCCESS) {
		failed = true;
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return nullptr;
	}
	defer (if (failed) cmnRemove(&gMtl4AllocationStorage.gpuDirectLookup, metadata.gpuPtr));

	if (memory != GPU_MEMORY_GPU) {
		Mtl4AddressRange cpuAddressRange = { /*start=*/metadata.cpuPtr, /*length=*/metadata.size };
		cmnInsert(&gMtl4AllocationStorage.cpuRangeLookup, cpuAddressRange, handle, &localResult);
		if (localResult != CMN_SUCCESS) {
			failed = true;
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return nullptr;
		}
		defer (if (failed) cmnRemove(&gMtl4AllocationStorage.cpuRangeLookup, cpuAddressRange));

		cmnInsert(&gMtl4AllocationStorage.cpuDirectLookup, metadata.cpuPtr, handle, &localResult);
		if (localResult != CMN_SUCCESS) {
			failed = true;
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return nullptr;
		}
		defer (if (failed) cmnRemove(&gMtl4AllocationStorage.cpuDirectLookup, metadata.cpuPtr));
	}

	if (!metadata.isSmallAllocation) {
		mtl4AddAllocationToResidencySet(metadata.backing);
	}

	if (memory == GPU_MEMORY_GPU) {
		CMN_SET_RESULT(result, GPU_SUCCESS);
		return (void*)metadata.gpuPtr;
	} else {
		CMN_SET_RESULT(result, GPU_SUCCESS);
		return (void*)metadata.cpuPtr;
	}
}

void mtl4Free(void* ptr) {
	CmnScopedNSAutoreleasePool pool;

	if (ptr == nullptr) {
		return;
	}

	bool couldFindMetadata;
	Mtl4AllocationHandle handle = mtl4AllocationHandleOf(ptr, false, &couldFindMetadata);
	if (!couldFindMetadata) {
		return;
	}

	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFrom(handle, nullptr);
	if (metadata == nullptr) {
		return;
	}
	cmnAtomicStore(&metadata->sheduledForDeletion, true);
	mtl4FreeAssociatedTextures(metadata);
	mtl4ScheduleAllocationForDeletion(handle);

	mtl4ReleaseAllocationMetadata();
	mtl4CheckForResourceDeletion();
}

void* mtl4HostToDevicePointer(void* ptr, GpuResult* result) {
	CmnScopedNSAutoreleasePool pool;

	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFrom(ptr, true);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return nullptr;
	}
	defer (mtl4ReleaseAllocationMetadata());

	CMN_SET_RESULT(result, GPU_SUCCESS);

	size_t offsetFromBase = mtl4CpuPtrOffsetFromBase(metadata, ptr);
	return (void*)(metadata->gpuPtr + offsetFromBase);
}

id<MTLHeap> mtl4AllocateHeap(size_t size, size_t align, GpuMemory memory, GpuResult* result) {
	(void)align;

	MTLResourceOptions resourceOptions = gMtl4ResourceOptionsFor[memory];

	// TODO: Overallocate to ensure alignment
	MTLHeapDescriptor* heapDescriptor = [[MTLHeapDescriptor new] autorelease];
	if (heapDescriptor == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return nil;
	}

	heapDescriptor.type = MTLHeapTypePlacement;
	heapDescriptor.size = size;
	heapDescriptor.resourceOptions = resourceOptions;

	id<MTLHeap> heap = [gMtl4Context.device
		newHeapWithDescriptor:heapDescriptor];
	if (heap == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return nil;
	}

	mtl4AddAllocationToResidencySet(heap);

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return heap;
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

Mtl4AllocationHandle mtl4AllocationHandleOf(void* ptr, bool attemptRangeBasedLookup, bool* couldFindMetadata) {
	bool localCouldFindMetadata;
	Mtl4AllocationHandle handle;

	handle = mtl4AllocationHandleOfCpuPtr(ptr, attemptRangeBasedLookup, &localCouldFindMetadata);
	if (!localCouldFindMetadata) {
		handle =  mtl4AllocationHandleOfGpuPtr(ptr, attemptRangeBasedLookup, &localCouldFindMetadata);
	}

	CMN_SET_NULLABLE(couldFindMetadata, localCouldFindMetadata);
	return handle;
}

Mtl4AllocationHandle mtl4AllocationHandleOfCpuPtr(void* ptr, bool attemptRangeBasedLookup, bool* couldFindMetadata) {

	CmnScopedStorageSyncLockRead guard(&gMtl4AllocationStorage.sync);

	bool didFindElement;
	Mtl4AllocationHandle handle;

	// NOTE: Attempt fast lookup. Will find the address if no offset has beed applied to the pointer.
	handle = cmnGet(&gMtl4AllocationStorage.cpuDirectLookup, (uintptr_t)ptr, &didFindElement);
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

	handle = cmnGet(&gMtl4AllocationStorage.cpuRangeLookup, range, &didFindElement);
	if (didFindElement) {
		CMN_SET_NULLABLE(couldFindMetadata, true);
		return handle;
	}

	CMN_SET_NULLABLE(couldFindMetadata, false);
	return {};
}

Mtl4AllocationHandle mtl4AllocationHandleOfGpuPtr(void* ptr, bool attemptRangeBasedLookup, bool* couldFindMetadata) {

	CmnScopedStorageSyncLockRead guard(&gMtl4AllocationStorage.sync);

	bool didFindElement;
	Mtl4AllocationHandle handle;

	// NOTE: Attempt fast lookup. Will find the address if no offset has beed applied to the pointer.
	handle = cmnGet(&gMtl4AllocationStorage.gpuDirectLookup, (uintptr_t)ptr, &didFindElement);
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

	handle = cmnGet(&gMtl4AllocationStorage.gpuRangeLookup, range, &didFindElement);
	if (didFindElement) {
		CMN_SET_NULLABLE(couldFindMetadata, true);
		return handle;
	}

	CMN_SET_NULLABLE(couldFindMetadata, false);
	return {};
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

Mtl4AllocationMetadata* mtl4AcquireAllocationMetadataFromGpuPtr(void* ptr, bool attemptRangeBasedLookup) {
	bool couldFindMetadata;
	Mtl4AllocationHandle handle = mtl4AllocationHandleOfGpuPtr(ptr, attemptRangeBasedLookup, &couldFindMetadata);
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

	CmnChainIterator<Mtl4Texture, 14> iter;
	cmnCreateChainIterator(&metadata->relatedTextures, &iter);

	Mtl4Texture* texture;
	while (cmnIterate(&iter, &texture)) {
		mtl4FreeTexture(mtl4HandleToGpuTexture(*texture));
	}

	cmnDestroyChain(&metadata->relatedTextures, cmnPoolAllocator(&gMtl4AllocationStorage.miscPool));
}

bool mtl4IsAllocationScheduledForDeletion(Mtl4AllocationMetadata* metadata) {
	return cmnAtomicLoad(&metadata->sheduledForDeletion);
}

void mtl4DestroyAllocation(Mtl4AllocationHandle handle) {
	bool wasHandleValid;
	Mtl4AllocationMetadata* metadata = &cmnGet(&gMtl4AllocationStorage.allocations, handle, &wasHandleValid);
	if (!wasHandleValid) {
		return;
	}

	assert(metadata->sheduledForDeletion);


	mtl4FreeAssociatedTextures(metadata);

	[metadata->buffer release];

	if (metadata->isSmallAllocation) {
		tlsfFree(metadata->small.pool, metadata->small.allocation);
	} else {
		[metadata->backing release];
	}

	if (metadata->memory != GPU_MEMORY_GPU) {
		Mtl4AddressRange cpuRange;
		cpuRange.start = metadata->cpuPtr;
		cpuRange.length = 0;
		
		cmnRemove(&gMtl4AllocationStorage.cpuRangeLookup, cpuRange);
		cmnRemove(&gMtl4AllocationStorage.cpuDirectLookup, metadata->cpuPtr);
	}

	Mtl4AddressRange gpuRange;
	gpuRange.start = metadata->gpuPtr;
	gpuRange.length = 0;
	cmnRemove(&gMtl4AllocationStorage.gpuRangeLookup, gpuRange);
	cmnRemove(&gMtl4AllocationStorage.gpuDirectLookup, metadata->gpuPtr);

	cmnRemove(&gMtl4AllocationStorage.allocations, handle);
}

