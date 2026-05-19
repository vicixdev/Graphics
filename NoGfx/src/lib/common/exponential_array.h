#ifndef CMN_EXPONENTIALARRAY_H
#define CMN_EXPONENTIALARRAY_H

#include <lib/common/common.h>
#include <lib/common/allocator.h>

#include <strings.h>
#include <assert.h>

#if CMN_ARCHITECTURE_BITS != 64
	#panic CmnExponentialArray requires a 64 bit architecture.
#endif

#define CMN_EXPONENTIALARRAY_POINTER_SIZE 64


template <typename T, size_t N = 15, size_t S = 5>
struct CmnExponentialArray;


// Initializes an exponential array.
//
// Inputs:
// - array: Array to initialize.
// - backingAllocator: Allocator used for bucket allocations.
// - result: Optional operation result.
//
// Results:
// - CMN_SUCCESS: Initialization succeeded.
// - CMN_OUT_OF_MEMORY: Backing allocator ran out of memory.
template <typename T, size_t N, size_t S> void cmnCreateExponentialArray(CmnExponentialArray<T, N, S>* array, CmnAllocator backingAllocator, CmnResult* result);

// Changes the logical length of an exponential array.
//
// Inputs:
// - array: Array to resize.
// - length: New logical length.
// - result: Optional operation result.
//
// Results:
// - CMN_SUCCESS: Resize succeeded.
// - CMN_OUT_OF_MEMORY: Backing allocator ran out of memory.
//
// Returns:
// - true on success.
template <typename T, size_t N, size_t S> bool cmnResize(CmnExponentialArray<T, N, S>* array, size_t length, CmnResult* result);

// Writes value at index.
//
// Inputs:
// - array: Target array.
// - index: Destination index.
// - value: Value to store.
template <typename T, size_t N, size_t S> void cmnSet(CmnExponentialArray<T, N, S>* array, size_t index, const T& value);

// Returns the value reference at index.
//
// Inputs:
// - array: Target array.
// - index: Source index.
//
// Returns:
// - Mutable reference to stored value.
template <typename T, size_t N, size_t S>   T& cmnGet(CmnExponentialArray<T, N, S>* array, size_t index);

// Appends value at the end of the array.
//
// Inputs:
// - array: Target array.
// - value: Value to append.
// - result: Optional operation result.
//
// Results:
// - CMN_SUCCESS: Append succeeded.
// - CMN_OUT_OF_MEMORY: Backing allocator ran out of memory.
//
// Returns:
// - true on success.
template <typename T, size_t N, size_t S> bool cmnAppend(CmnExponentialArray<T, N, S>* array, const T& value, CmnResult* result);

// Returns a reference to the last logical element.
//
// Inputs:
// - array: Target array.
//
// Returns:
// - Mutable reference to the last element.
template <typename T, size_t N, size_t S> T& cmnLast(CmnExponentialArray<T, N, S>* array);

// Removes the last logical element.
//
// Inputs:
// - array: Target array.
template <typename T, size_t N, size_t S> void cmnPop(CmnExponentialArray<T, N, S>* array);

// Iterator over the elements of an exponential array.
template <typename T, size_t N = 15, size_t S = 5>
struct CmnExponentialArrayIterator {
	CmnExponentialArray<T, N, S>* array;
	size_t currentIndex;
};

// Initializes an exponential array iterator at the beginning.
//
// Inputs:
// - array: Array to iterate.
// - iter: Iterator to initialize.
template <typename T, size_t N, size_t S>
void cmnCreateExponentialArrayIterator(CmnExponentialArray<T, N, S>* array, CmnExponentialArrayIterator<T, N, S>* iter);

// Advances the iterator and returns the next element.
//
// Inputs:
// - iter: Iterator to advance.
// - value: Output pointer to the next element.
//
// Returns:
// - true when a next element was found.
// - false when iteration is complete.
template <typename T, size_t N, size_t S>
bool cmnIterate(CmnExponentialArrayIterator<T, N, S>* iter, T** value);

// Maps a linear index to bucket and element indices.
//
// Inputs:
// - index: Linear index.
// - bucketIndex: Output bucket index.
// - elementIndex: Output index within bucket.
inline void cmnDecomposeExponentialArrayIndex(size_t index, size_t firstBucketBitCount, size_t* bucketIndex, size_t* elementIndex);


// Array-like container backed by exponentially growing buckets.
template <typename T, size_t N, size_t S>
struct CmnExponentialArray {
	CmnAllocator	backingAllocator;

	T* buckets[N];
	// Current logical element count.
	size_t length;
	size_t last_filled_bucket;

	const T& operator[](size_t index) const {
		return cmnGet<T, N, S>((CmnExponentialArray<T, N, S>*)this, index);
	}

	T& operator[](size_t index) {
		return cmnGet<T, N, S>(this, index);
	}
};

#include "exponential_array.inc"

#endif

