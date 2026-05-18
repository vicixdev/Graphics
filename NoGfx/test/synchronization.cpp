#include "test.h"

#include <pthread.h>
#include <sched.h>

#include <lib/common/atomic.h>
#include <lib/common/condition.h>
#include <lib/common/mutex.h>
#include <lib/common/rw_mutex.h>
#include <lib/common/semaphore.h>

typedef struct MutexCounterContext {
	CmnMutex mutex;
	size_t counter;
	size_t iterations;
} MutexCounterContext;

static void* mutexCounterThreadProc(void* ptr) {
	MutexCounterContext* context = (MutexCounterContext*)ptr;

	for (size_t i = 0; i < context->iterations; i++) {
		cmnMutexLock(&context->mutex);
		context->counter++;
		cmnMutexUnlock(&context->mutex);
	}

	return nullptr;
}

void checkMutexMutualExclusionWithPthreads(Test* test) {
	const size_t threadCount = 6;
	const size_t iterations = 20000;

	MutexCounterContext context = {};
	context.iterations = iterations;

	pthread_t threads[threadCount];
	for (size_t i = 0; i < threadCount; i++) {
		int createResult = pthread_create(&threads[i], nullptr, mutexCounterThreadProc, &context);
		TEST_ASSERT(test, createResult == 0);
	}

	for (size_t i = 0; i < threadCount; i++) {
		int joinResult = pthread_join(threads[i], nullptr);
		TEST_ASSERT(test, joinResult == 0);
	}

	TEST_ASSERT(test, context.counter == threadCount * iterations);
}

typedef struct MutexTryLockContext {
	CmnMutex* mutex;
	bool didLock;
} MutexTryLockContext;

static void* mutexTryLockThreadProc(void* ptr) {
	MutexTryLockContext* context = (MutexTryLockContext*)ptr;

	context->didLock = cmnMutexTryLock(context->mutex);
	if (context->didLock) {
		cmnMutexUnlock(context->mutex);
	}

	return nullptr;
}

void checkMutexTryLockWhileLocked(Test* test) {
	CmnMutex mutex = {};
	cmnMutexLock(&mutex);

	MutexTryLockContext context = {};
	context.mutex = &mutex;

	pthread_t worker;
	int createResult = pthread_create(&worker, nullptr, mutexTryLockThreadProc, &context);
	TEST_ASSERT(test, createResult == 0);

	int joinResult = pthread_join(worker, nullptr);
	TEST_ASSERT(test, joinResult == 0);
	TEST_ASSERT(test, !context.didLock);

	cmnMutexUnlock(&mutex);
}

typedef struct ConditionSignalContext {
	CmnCondition condition;
	CmnMutex mutex;
	bool ready;
	bool woke;
	uint32_t waiterStarted;
} ConditionSignalContext;

static void* conditionWaitThreadProc(void* ptr) {
	ConditionSignalContext* context = (ConditionSignalContext*)ptr;

	cmnMutexLock(&context->mutex);
	cmnAtomicStore(&context->waiterStarted, 1u, CMN_RELEASE);
	while (!context->ready) {
		cmnConditionWait(&context->condition, &context->mutex);
	}
	context->woke = true;
	cmnMutexUnlock(&context->mutex);

	return nullptr;
}

void checkConditionSignalWakesWaiter(Test* test) {
	ConditionSignalContext context = {};

	pthread_t worker;
	int createResult = pthread_create(&worker, nullptr, conditionWaitThreadProc, &context);
	TEST_ASSERT(test, createResult == 0);

	while (cmnAtomicLoad(&context.waiterStarted, CMN_ACQUIRE) == 0u) {
		sched_yield();
	}

	cmnMutexLock(&context.mutex);
	context.ready = true;
	cmnConditionSignal(&context.condition);
	cmnMutexUnlock(&context.mutex);

	int joinResult = pthread_join(worker, nullptr);
	TEST_ASSERT(test, joinResult == 0);
	TEST_ASSERT(test, context.woke);
}

void checkConditionWaitTimeout(Test* test) {
	CmnCondition condition = {};
	CmnMutex mutex = {};

	cmnMutexLock(&mutex);
	bool didWake = cmnConditionWaitWithTimeout(&condition, &mutex, 1000000);
	cmnMutexUnlock(&mutex);

	TEST_ASSERT(test, !didWake);
}

typedef struct RWReadersContext {
	CmnRWMutex rwMutex;
	CmnMutex statsMutex;
	uint32_t activeReaders;
	uint32_t enteredReaders;
	uint32_t maxReaders;
	uint32_t releaseReaders;
} RWReadersContext;

static void* rwReaderThreadProc(void* ptr) {
	RWReadersContext* context = (RWReadersContext*)ptr;

	cmnRWMutexLockRead(&context->rwMutex);

	cmnMutexLock(&context->statsMutex);
	context->activeReaders++;
	context->enteredReaders++;
	if (context->activeReaders > context->maxReaders) {
		context->maxReaders = context->activeReaders;
	}
	cmnMutexUnlock(&context->statsMutex);

	while (cmnAtomicLoad(&context->releaseReaders, CMN_ACQUIRE) == 0u) {
		sched_yield();
	}

	cmnMutexLock(&context->statsMutex);
	context->activeReaders--;
	cmnMutexUnlock(&context->statsMutex);

	cmnRWMutexUnlockRead(&context->rwMutex);
	return nullptr;
}

void checkRWMutexAllowsConcurrentReaders(Test* test) {
	const size_t threadCount = 4;
	RWReadersContext context = {};

	pthread_t readers[threadCount];
	for (size_t i = 0; i < threadCount; i++) {
		int createResult = pthread_create(&readers[i], nullptr, rwReaderThreadProc, &context);
		TEST_ASSERT(test, createResult == 0);
	}

	for (;;) {
		cmnMutexLock(&context.statsMutex);
		bool allEntered = context.enteredReaders == threadCount;
		cmnMutexUnlock(&context.statsMutex);

		if (allEntered) {
			break;
		}

		sched_yield();
	}

	cmnMutexLock(&context.statsMutex);
	uint32_t maxReaders = context.maxReaders;
	cmnMutexUnlock(&context.statsMutex);
	TEST_ASSERT(test, maxReaders > 1);

	cmnAtomicStore(&context.releaseReaders, 1u, CMN_RELEASE);

	for (size_t i = 0; i < threadCount; i++) {
		int joinResult = pthread_join(readers[i], nullptr);
		TEST_ASSERT(test, joinResult == 0);
	}
}

typedef struct RWTryLockContext {
	CmnRWMutex* rwMutex;
	bool didReadLock;
	bool didWriteLock;
} RWTryLockContext;

static void* rwTryLockBothThreadProc(void* ptr) {
	RWTryLockContext* context = (RWTryLockContext*)ptr;

	context->didReadLock = cmnRWMutexTryLockRead(context->rwMutex);
	if (context->didReadLock) {
		cmnRWMutexUnlockRead(context->rwMutex);
	}

	context->didWriteLock = cmnRWMutexTryLockWrite(context->rwMutex);
	if (context->didWriteLock) {
		cmnRWMutexUnlockWrite(context->rwMutex);
	}

	return nullptr;
}

static void* rwTryLockWriteThreadProc(void* ptr) {
	RWTryLockContext* context = (RWTryLockContext*)ptr;

	context->didWriteLock = cmnRWMutexTryLockWrite(context->rwMutex);
	if (context->didWriteLock) {
		cmnRWMutexUnlockWrite(context->rwMutex);
	}

	return nullptr;
}

void checkRWMutexWriteExclusion(Test* test) {
	CmnRWMutex rwMutex = {};

	cmnRWMutexLockWrite(&rwMutex);

	RWTryLockContext writerHeldContext = {};
	writerHeldContext.rwMutex = &rwMutex;

	pthread_t worker;
	int createResult = pthread_create(&worker, nullptr, rwTryLockBothThreadProc, &writerHeldContext);
	TEST_ASSERT(test, createResult == 0);

	int joinResult = pthread_join(worker, nullptr);
	TEST_ASSERT(test, joinResult == 0);
	TEST_ASSERT(test, !writerHeldContext.didReadLock);
	TEST_ASSERT(test, !writerHeldContext.didWriteLock);

	cmnRWMutexUnlockWrite(&rwMutex);

	cmnRWMutexLockRead(&rwMutex);

	RWTryLockContext readerHeldContext = {};
	readerHeldContext.rwMutex = &rwMutex;

	createResult = pthread_create(&worker, nullptr, rwTryLockWriteThreadProc, &readerHeldContext);
	TEST_ASSERT(test, createResult == 0);

	joinResult = pthread_join(worker, nullptr);
	TEST_ASSERT(test, joinResult == 0);
	TEST_ASSERT(test, !readerHeldContext.didWriteLock);

	cmnRWMutexUnlockRead(&rwMutex);
}

typedef struct SemaphoreConcurrencyContext {
	CmnSemaphore semaphore;
	CmnMutex stateMutex;
	uint32_t activeCount;
	uint32_t maxActiveCount;
	uint32_t limit;
	uint32_t iterations;
	bool violation;
} SemaphoreConcurrencyContext;

static void* semaphoreWorkerThreadProc(void* ptr) {
	SemaphoreConcurrencyContext* context = (SemaphoreConcurrencyContext*)ptr;

	for (uint32_t i = 0; i < context->iterations; i++) {
		cmnSemaphoreWait(&context->semaphore);

		cmnMutexLock(&context->stateMutex);
		context->activeCount++;
		if (context->activeCount > context->limit) {
			context->violation = true;
		}
		if (context->activeCount > context->maxActiveCount) {
			context->maxActiveCount = context->activeCount;
		}
		cmnMutexUnlock(&context->stateMutex);

		for (size_t spin = 0; spin < 256; spin++) {
			__builtin_arm_isb(0xF);
		}
		sched_yield();

		cmnMutexLock(&context->stateMutex);
		context->activeCount--;
		cmnMutexUnlock(&context->stateMutex);

		cmnSemaphorePost(&context->semaphore);
	}

	return nullptr;
}

void checkSemaphoreAllowsMaximumConcurrentAcquisitions(Test* test) {
	const size_t threadCount = 8;
	const uint32_t limit = 3;
	const uint32_t iterations = 2000;

	SemaphoreConcurrencyContext context = {};
	cmnCreateSemaphore(&context.semaphore, limit);
	context.limit = limit;
	context.iterations = iterations;

	pthread_t workers[threadCount];
	for (size_t i = 0; i < threadCount; i++) {
		int createResult = pthread_create(&workers[i], nullptr, semaphoreWorkerThreadProc, &context);
		TEST_ASSERT(test, createResult == 0);
	}

	for (size_t i = 0; i < threadCount; i++) {
		int joinResult = pthread_join(workers[i], nullptr);
		TEST_ASSERT(test, joinResult == 0);
	}

	TEST_ASSERT(test, !context.violation);
	TEST_ASSERT(test, context.maxActiveCount == limit);
}

void checkSemaphoreTryWaitFailsWhenCountIsZero(Test* test) {
	CmnSemaphore semaphore = {};
	cmnCreateSemaphore(&semaphore, 1);

	bool didAcquire = cmnSemaphoreTryWait(&semaphore);
	TEST_ASSERT(test, didAcquire);

	bool didAcquireAgain = cmnSemaphoreTryWait(&semaphore);
	TEST_ASSERT(test, !didAcquireAgain);

	cmnSemaphorePost(&semaphore);

	didAcquireAgain = cmnSemaphoreTryWait(&semaphore);
	TEST_ASSERT(test, didAcquireAgain);

	cmnSemaphorePost(&semaphore);
}
