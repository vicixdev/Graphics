#ifndef CMN_HANDLEMAP_H
#define CMN_HANDLEMAP_H

#include <limits.h>
#include <lib/common/common.h>
#include <lib/common/allocator.h>
#include <lib/common/exponential_array.h>

// Opaque generational handle used to reference CmnHandleMap entries.
typedef struct CmnHandle {
	uint32_t	index		: 32;
	uint32_t	generation	: 32;
} CmnHandle;

// Checks whether a handle is zero.
inline bool cmnIsZero(CmnHandle handle) {
	return handle.index == 0 && handle.generation == 0;
}

// Storage bucket used internally by CmnHandleMap.
template <typename T>
struct CmnHandleMapBucket {
	bool		isInUse;
	uint32_t	generation;
	union {
		// If isInUse
		// Stored element when the bucket is in use.
		T		element;
		// If not isInUse
		// Next free bucket index when the bucket is free.
		uint32_t	nextFreeIndex;
	};
};

// Associative container using generational handles for stable references.
template <typename T>
struct CmnHandleMap {
	CmnExponentialArray<CmnHandleMapBucket<T>>	buckets;
	uint32_t					firstFree;
	T						defaultElement;
};

// Initializes a handle map.
//
// Inputs:
// - map: Map to initialize.
// - backingAllocator: Allocator used for backing storage.
// - defaultElement: Value returned for invalid handle lookups.
// - result: Optional operation result.
//
// Results:
// - CMN_SUCCESS: Initialization succeeded.
// - CMN_OUT_OF_MEMORY: Backing allocator ran out of memory.
template <typename T>
void cmnCreateHandleMap(CmnHandleMap<T>* map, CmnAllocator backingAllocator, T defaultElement, CmnResult* result);

// Inserts an element and returns its generated handle.
//
// Inputs:
// - map: Target map.
// - element: Element to insert.
// - result: Optional operation result.
//
// Results:
// - CMN_SUCCESS: Insert succeeded.
// - CMN_OUT_OF_MEMORY: Backing allocator ran out of memory while growing storage.
// - CMN_OUT_OF_RESOURCE_SLOTS: No more handle slots are available.
//
// Returns:
// - Generated handle.
template <typename T>
CmnHandle cmnInsert(CmnHandleMap<T>* map, const T& element, CmnResult* result);

// Checks whether a handle is currently valid.
//
// Inputs:
// - map: Target map.
// - handle: Handle to validate.
//
// Returns:
// - true when the handle is valid.
template <typename T>
bool cmnIsValid(const CmnHandleMap<T>* map, CmnHandle handle);

// Returns the element referenced by handle.
//
// Inputs:
// - map: Target map.
// - handle: Handle to resolve.
// - wasHandleValid: Optional output validity flag.
//
// Returns:
// - Element reference when valid, or defaultElement otherwise.
template <typename T>
T& cmnGet(CmnHandleMap<T>* map, CmnHandle handle, bool* wasHandleValid);

// Removes the element referenced by handle.
//
// Inputs:
// - map: Target map.
// - handle: Handle to remove.
template <typename T>
void cmnRemove(CmnHandleMap<T>* map, CmnHandle handle);

// Iterator over all live elements in a handle map.
template <typename T>
struct CmnHandleMapIterator {
	// Map being iterated.
	CmnHandleMap<T>* map;
	// Current bucket index in the map.
	uint32_t currentBucketIndex;
};

// Initializes a handle map iterator at the beginning.
//
// Inputs:
// - map: Map to iterate.
// - iter: Iterator to initialize.
template <typename T>
void cmnCreateHandleMapIterator(CmnHandleMap<T>* map, CmnHandleMapIterator<T>* iter);

// Advances the iterator and returns the next live element.
//
// Inputs:
// - iter: Iterator to advance.
// - value: Output pointer to the next element.
//
// Returns:
// - true when a next element was found.
// - false when iteration is complete.
template <typename T>
bool cmnIterate(CmnHandleMapIterator<T>* iter, T** value);

#include "handle_map.inc"

#endif // CMN_HANDLEMAP_H

