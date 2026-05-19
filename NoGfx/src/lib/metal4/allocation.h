#ifndef GPU_POINTERRANGETREE_H
#define GPU_POINTERRANGETREE_H

#include <gpu/gpu.h>
#include <Metal/Metal.h>

#include <lib/common/page.h>
#include <lib/common/chain.h>
#include <lib/common/btree.h>
#include <lib/common/pointer_map.h>
#include <lib/common/element_pool.h>
#include <lib/common/storage_sync.h>
#include <lib/metal4/textures.h>


// NOTE: 2 * cacheline
#define MTL4_ALLOCATIONS_MISCPOOLSLOT_SIZE 128
#define MTL4_ALLOCATIONS_NODESPOLLSLOT_SIZE sizeof(CmnBTreeNode<Mtl4AddressRange, Mtl4AllocationHandle>)


typedef CmnHandle Mtl4AllocationHandle;

typedef struct Mtl4AddressRange {
	uintptr_t	start;
	size_t		length;
} Mtl4AddressRange;

typedef struct Mtl4AllocationMetadata {
	GpuMemory	memory;
	uintptr_t	cpuPtr;
	uintptr_t	gpuPtr;
	size_t		size;

	bool		sheduledForDeletion;

	id<MTLHeap>	backing;
	id<MTLBuffer>	buffer;

	CmnChain<Mtl4Texture, 14> relatedTextures;
} Mtl4AllocationMetadata;

static_assert(
	sizeof(CmnChainNode<Mtl4Texture, 14>) <= MTL4_ALLOCATIONS_MISCPOOLSLOT_SIZE,
	"A chain node should be able to be contained in the misc pool."
);

typedef struct Mtl4AllocationStorage {
	CmnPage		arenaPage;
	CmnPage		miscPoolPage;
	CmnPage		nodesPoolPage;

	CmnArena	arena;
	CmnPool		miscPool;
	CmnPool		nodesPool;

	CmnPointerMap	<Mtl4AllocationHandle>				gpuDirectLookup;
	CmnBTree	<Mtl4AddressRange, Mtl4AllocationHandle>	gpuRangeLookup;
	CmnPointerMap	<Mtl4AllocationHandle>				cpuDirectLookup;
	CmnBTree	<Mtl4AddressRange, Mtl4AllocationHandle>	cpuRangeLookup;

	CmnHandleMap	<Mtl4AllocationMetadata>	allocations;

	CmnStorageSync	sync;
} Mtl4AllocationStorage;
extern Mtl4AllocationStorage gMtl4AllocationStorage;

static_assert(
	sizeof(CmnBTreeNode<Mtl4AddressRange, Mtl4AllocationHandle>) <= MTL4_ALLOCATIONS_NODESPOLLSLOT_SIZE,
	"A lookup tree node should be able to be contained in the nodes poll."
);

void mtl4InitAllocationStorage(GpuResult* result);
void mtl4FiniAllocationStorage(void);

void* mtl4Malloc(size_t size, size_t align, GpuMemory memory, GpuResult* result);
void  mtl4Free(void* ptr);
void* mtl4HostToDevicePointer(void* ptr, GpuResult* result);

id<MTLHeap> mtl4AllocateHeap(size_t size, size_t align, GpuMemory memory, GpuResult* result);

inline bool mtl4IsCpuAddress(Mtl4AllocationMetadata* metadata, void* ptr) {
	return metadata->cpuPtr <= (uintptr_t)ptr && (uintptr_t)ptr < metadata->cpuPtr + metadata->size;
}
inline bool mtl4IsGpuAddress(Mtl4AllocationMetadata* metadata, void* ptr) {
	return metadata->gpuPtr <= (uintptr_t)ptr && (uintptr_t)ptr < metadata->gpuPtr + metadata->size;
}

inline size_t mtl4GpuPtrOffsetFromBase(Mtl4AllocationMetadata* metadata,void* gpuPtr) {
	return (uintptr_t)gpuPtr - metadata->gpuPtr;
}
inline size_t mtl4CpuPtrOffsetFromBase(Mtl4AllocationMetadata* metadata,void* cpuPtr) {
	return (uintptr_t)cpuPtr - metadata->cpuPtr;
}

Mtl4AllocationMetadata* mtl4AcquireAllocationMetadataFrom(Mtl4AllocationHandle handle, bool* wasHandleValid);
void mtl4ReleaseAllocationMetadata(void);

Mtl4AllocationHandle mtl4AllocationHandleOf(void* ptr, bool attemptRangeBasedLookup, bool* couldFindMetadata);
Mtl4AllocationHandle mtl4AllocationHandleOfCpuPtr(void* ptr, bool attemptRangeBasedLookup, bool* couldFindMetadata);
Mtl4AllocationHandle mtl4AllocationHandleOfGpuPtr(void* ptr, bool attemptRangeBasedLookup, bool* couldFindMetadata);

Mtl4AllocationMetadata* mtl4AcquireAllocationMetadataFrom(void* ptr, bool attemptRangeBasedLookup);
Mtl4AllocationMetadata* mtl4AcquireAllocationMetadataFromCpuPtr(void* ptr, bool attemptRangeBasedLookup);
Mtl4AllocationMetadata* mtl4AcquireAllocationMetadataFromGpuPtr(void* ptr, bool attemptRangeBasedLookup);

void mtl4AssociateTextureToAllocation(Mtl4AllocationMetadata* metadata, Mtl4Texture texture, GpuResult* result);
void mtl4FreeAssociatedTextures(Mtl4AllocationMetadata* metadata);

bool mtl4IsAllocationScheduledForDeletion(Mtl4AllocationMetadata* metadata);

// NOTE: Requires a deletion lock in gMtl4AllocationStorage.sync
void mtl4DestroyAllocation(Mtl4AllocationHandle handle);

// NOTE: This is an HACK, since eq and cmp are not symmetrical. This works because the implementation of BTree always
//	compares keys and values with the same order: keys on the right, values on the left.
template<>
struct CmnTypeTraits<Mtl4AddressRange> {
	static bool eq(const Mtl4AddressRange& left, const Mtl4AddressRange& right) {
		return right.start >= left.start &&
			right.start + right.length <= left.start + left.length;
	}

	static CmnCmp cmp(const Mtl4AddressRange& left, const Mtl4AddressRange& right) {
		if (right.start < left.start) {
			return CMN_MORE;
		}
		if (right.start + right.length > left.start + left.length) {
			return CMN_LESS;
		}
		return CMN_EQUALS;
	}
};

#endif

