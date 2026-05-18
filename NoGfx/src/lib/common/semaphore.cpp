#include "semaphore.h"

void cmnCreateSemaphore(CmnSemaphore* semaphore, uint32_t initialCount) {
	semaphore->count = initialCount;
}

void cmnSemaphoreWait(CmnSemaphore* semaphore) {
	cmnMutexLock(&semaphore->mutex);

	while (semaphore->count == 0) {
		cmnConditionWait(&semaphore->condition, &semaphore->mutex);
	}

	semaphore->count--;
	cmnMutexUnlock(&semaphore->mutex);
}

bool cmnSemaphoreTryWait(CmnSemaphore* semaphore) {
	cmnMutexLock(&semaphore->mutex);

	bool didAcquire = false;
	if (semaphore->count > 0) {
		semaphore->count--;
		didAcquire = true;
	}

	cmnMutexUnlock(&semaphore->mutex);
	return didAcquire;
}

void cmnSemaphorePost(CmnSemaphore* semaphore) {
	cmnMutexLock(&semaphore->mutex);
	semaphore->count++;
	cmnConditionSignal(&semaphore->condition);
	cmnMutexUnlock(&semaphore->mutex);
}
