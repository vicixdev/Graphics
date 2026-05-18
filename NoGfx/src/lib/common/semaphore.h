#ifndef CMN_SEMAPHORE_H
#define CMN_SEMAPHORE_H

#include <lib/common/condition.h>
#include <lib/common/mutex.h>

// Counting semaphore allowing up to `count` concurrent resource acquisitions.
// A semaphore is initialized with the maximum number of available resources.
// Each wait acquires one resource and each post releases one resource.
typedef struct CmnSemaphore {
	CmnMutex mutex;
	CmnCondition condition;
	uint32_t count;
} CmnSemaphore;

// Initializes a semaphore with an initial available count.
// The semaphore is assumed to be zero-initialized before this call.
void cmnCreateSemaphore(CmnSemaphore* semaphore, uint32_t initialCount);

// Acquires a resource from the semaphore, blocking until one is available.
void cmnSemaphoreWait(CmnSemaphore* semaphore);

// Tries to acquire a resource without blocking.
// Returns true when the resource was acquired.
bool cmnSemaphoreTryWait(CmnSemaphore* semaphore);

// Releases a resource back to the semaphore.
void cmnSemaphorePost(CmnSemaphore* semaphore);

#endif // CMN_SEMAPHORE_H
