#include "gpu_common.h"

#include <cstdlib>
#include <pthread.h>
#include <sched.h>
#include <lib/common/atomic.h>

void checkGpuMallocAndFree(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);

	void* ptr = gpuMalloc(1024, 16, GPU_MEMORY_DEFAULT, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, ptr != nullptr);

	gpuFree(ptr);

	gpuDeinit();
}

void checkGpuMallocAndFreeGpuMemory(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);

	void* ptr = gpuMalloc(1024, 16, GPU_MEMORY_GPU, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, ptr != nullptr);

	gpuFree(ptr);

	gpuDeinit();
}

void checkGpuHostToDevicePointerOnGpuMemory(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);

	void* ptr = gpuMalloc(256, 16, GPU_MEMORY_GPU, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, ptr != nullptr);

	void* devicePtr = gpuHostToDevicePointer(ptr, &result);

	TEST_ASSERT(test, result == GPU_ALLOCATION_MEMORY_IS_GPU);
	TEST_ASSERT(test, devicePtr == nullptr);

	gpuFree(ptr);

	gpuDeinit();
}

void checkGpuFreeInvalidPointer(Test* test) {
	(void)test;

	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);

	int dummy;
	gpuFree(&dummy); // Should not crash

	gpuDeinit();
}

void checkGpuHostToDevicePointer(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);

	void* ptr = gpuMalloc(256, 16, GPU_MEMORY_DEFAULT, &result);
	if (ptr == nullptr) {
		return;
	}

	void* devicePtr = gpuHostToDevicePointer(ptr, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, devicePtr != nullptr);

	gpuFree(ptr);

	gpuDeinit();
}

void checkGpuHostToDevicePointerWithOffset(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);

	void* basePtr = gpuMalloc(256, 16, GPU_MEMORY_DEFAULT, &result);
	if (basePtr == nullptr) {
		return;
	}

	void* baseDevicePtr = gpuHostToDevicePointer(basePtr, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, baseDevicePtr != nullptr);

	void* offsetPtr = (void*)((uintptr_t)basePtr + 128);
	void* devicePtrWithOffset = gpuHostToDevicePointer(offsetPtr, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, devicePtrWithOffset != nullptr);

	uintptr_t offset = (uintptr_t)devicePtrWithOffset - (uintptr_t)baseDevicePtr;
	TEST_ASSERT(test, offset == 128);

	gpuFree(basePtr);

	gpuDeinit();
}

typedef struct GpuAllocationCreatorContext {
	size_t bytes;
	size_t align;
	GpuMemory memory;

	void* ptr;
	GpuResult createResult;
	uint32_t created;
} GpuAllocationCreatorContext;

typedef struct GpuAllocationDestroyerContext {
	GpuAllocationCreatorContext* creator;
	uint32_t destroyed;
} GpuAllocationDestroyerContext;

static void* gpuAllocationCreatorThreadProc(void* ptr) {
	GpuAllocationCreatorContext* context = (GpuAllocationCreatorContext*)ptr;

	context->ptr = gpuMalloc(context->bytes, context->align, context->memory, &context->createResult);
	cmnAtomicStore(&context->created, 1u, CMN_RELEASE);

	return nullptr;
}

static void* gpuAllocationDestroyerThreadProc(void* ptr) {
	GpuAllocationDestroyerContext* context = (GpuAllocationDestroyerContext*)ptr;

	while (cmnAtomicLoad(&context->creator->created, CMN_ACQUIRE) == 0u) {
		sched_yield();
	}

	if (context->creator->createResult == GPU_SUCCESS && context->creator->ptr != nullptr) {
		gpuFree(context->creator->ptr);
	}

	cmnAtomicStore(&context->destroyed, 1u, CMN_RELEASE);
	return nullptr;
}

void checkGpuAllocationCreatedAndDestroyedOnDifferentThreads(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	GpuAllocationCreatorContext creatorContext = {};
	creatorContext.bytes = 4096;
	creatorContext.align = 16;
	creatorContext.memory = GPU_MEMORY_DEFAULT;

	GpuAllocationDestroyerContext destroyerContext = {};
	destroyerContext.creator = &creatorContext;

	pthread_t creatorThread;
	int createResult = pthread_create(&creatorThread, nullptr, gpuAllocationCreatorThreadProc, &creatorContext);
	TEST_ASSERT(test, createResult == 0);

	pthread_t destroyerThread;
	createResult = pthread_create(&destroyerThread, nullptr, gpuAllocationDestroyerThreadProc, &destroyerContext);
	TEST_ASSERT(test, createResult == 0);

	int joinResult = pthread_join(creatorThread, nullptr);
	TEST_ASSERT(test, joinResult == 0);

	joinResult = pthread_join(destroyerThread, nullptr);
	TEST_ASSERT(test, joinResult == 0);

	TEST_ASSERT(test, creatorContext.createResult == GPU_SUCCESS);
	TEST_ASSERT(test, creatorContext.ptr != nullptr);
	TEST_ASSERT(test, cmnAtomicLoad(&destroyerContext.destroyed, CMN_ACQUIRE) == 1u);

	gpuDeinit();
}

typedef struct GpuAllocationStressThreadContext {
	GpuStressGate* gate;
	size_t iterations;
	GpuMemory memory;
	bool expectHostToDeviceSuccess;
	uint32_t completed;
	uint32_t failed;
} GpuAllocationStressThreadContext;

typedef struct GpuHostPointerStressThreadContext {
	GpuStressGate* gate;
	void* basePtr;
	uintptr_t expectedOffset;
	size_t iterations;
	uint32_t completed;
	uint32_t failed;
} GpuHostPointerStressThreadContext;

static void* gpuAllocationStressThreadProc(void* ptr) {
	GpuAllocationStressThreadContext* context = (GpuAllocationStressThreadContext*)ptr;

	gpuWaitForStressStart(context->gate);

	for (size_t i = 0; i < context->iterations; i++) {
		GpuResult allocationResult = GPU_GENERAL_ERROR;
		size_t bytes = 256u + ((i & 7u) * 16u);
		void* allocation = gpuMalloc(bytes, 16, context->memory, &allocationResult);
		if (allocationResult != GPU_SUCCESS || allocation == nullptr) {
			context->failed = 1u;
			context->completed = 1u;
			return nullptr;
		}

		GpuResult pointerResult = GPU_GENERAL_ERROR;
		void* devicePtr = gpuHostToDevicePointer(allocation, &pointerResult);
		if (context->expectHostToDeviceSuccess) {
			if (pointerResult != GPU_SUCCESS || devicePtr == nullptr) {
				gpuFree(allocation);
				context->failed = 1u;
				context->completed = 1u;
				return nullptr;
			}
		} else {
			if (pointerResult != GPU_ALLOCATION_MEMORY_IS_GPU || devicePtr != nullptr) {
				gpuFree(allocation);
				context->failed = 1u;
				context->completed = 1u;
				return nullptr;
			}
		}

		gpuFree(allocation);
	}

	context->completed = 1u;
	return nullptr;
}

static void* gpuHostPointerStressThreadProc(void* ptr) {
	GpuHostPointerStressThreadContext* context = (GpuHostPointerStressThreadContext*)ptr;

	gpuWaitForStressStart(context->gate);

	for (size_t i = 0; i < context->iterations; i++) {
		GpuResult result = GPU_GENERAL_ERROR;
		void* mappedBase = gpuHostToDevicePointer(context->basePtr, &result);
		if (result != GPU_SUCCESS || mappedBase == nullptr) {
			context->failed = 1u;
			context->completed = 1u;
			return nullptr;
		}

		void* mappedOffset = gpuHostToDevicePointer((void*)((uintptr_t)context->basePtr + context->expectedOffset), &result);
		if (result != GPU_SUCCESS || mappedOffset == nullptr) {
			context->failed = 1u;
			context->completed = 1u;
			return nullptr;
		}

		uintptr_t offset = (uintptr_t)mappedOffset - (uintptr_t)mappedBase;
		if (offset != context->expectedOffset) {
			context->failed = 1u;
			context->completed = 1u;
			return nullptr;
		}
	}

	context->completed = 1u;
	return nullptr;
}

static void runGpuAllocationStress(Test* test, GpuMemory memory, bool expectHostToDeviceSuccess) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	const size_t threadCount = 8;
	const size_t iterations = 256;

	GpuStressGate gate = {};
	GpuAllocationStressThreadContext contexts[threadCount] = {};
	pthread_t threads[threadCount];

	for (size_t i = 0; i < threadCount; i++) {
		contexts[i].gate = &gate;
		contexts[i].iterations = iterations;
		contexts[i].memory = memory;
		contexts[i].expectHostToDeviceSuccess = expectHostToDeviceSuccess;

		int createResult = pthread_create(&threads[i], nullptr, gpuAllocationStressThreadProc, &contexts[i]);
		TEST_ASSERT(test, createResult == 0);
	}

	waitForGateReady(&gate, threadCount);
	cmnAtomicStore(&gate.start, 1u, CMN_RELEASE);

	for (size_t i = 0; i < threadCount; i++) {
		int joinResult = pthread_join(threads[i], nullptr);
		TEST_ASSERT(test, joinResult == 0);
		TEST_ASSERT(test, contexts[i].completed == 1u);
		TEST_ASSERT(test, contexts[i].failed == 0u);
	}

	gpuDeinit();
}

static void runGpuHostPointerStress(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	void* ptrCpu = gpuMalloc(512, 16, GPU_MEMORY_DEFAULT, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, ptrCpu != nullptr);

	const size_t threadCount = 6;
	const size_t iterations = 1024;

	GpuStressGate gate = {};
	GpuHostPointerStressThreadContext contexts[threadCount] = {};
	pthread_t threads[threadCount];

	for (size_t i = 0; i < threadCount; i++) {
		contexts[i].gate = &gate;
		contexts[i].basePtr = ptrCpu;
		contexts[i].expectedOffset = 128u;
		contexts[i].iterations = iterations;

		int createResult = pthread_create(&threads[i], nullptr, gpuHostPointerStressThreadProc, &contexts[i]);
		TEST_ASSERT(test, createResult == 0);
	}

	waitForGateReady(&gate, threadCount);
	cmnAtomicStore(&gate.start, 1u, CMN_RELEASE);

	for (size_t i = 0; i < threadCount; i++) {
		int joinResult = pthread_join(threads[i], nullptr);
		TEST_ASSERT(test, joinResult == 0);
		TEST_ASSERT(test, contexts[i].completed == 1u);
		TEST_ASSERT(test, contexts[i].failed == 0u);
	}

	gpuFree(ptrCpu);

	gpuDeinit();
}

void checkGpuConcurrentAllocationStressOnCpuMemory(Test* test) {
	runGpuAllocationStress(test, GPU_MEMORY_DEFAULT, true);
}

void checkGpuConcurrentAllocationStressOnGpuMemory(Test* test) {
	runGpuAllocationStress(test, GPU_MEMORY_GPU, false);
}

void checkGpuConcurrentHostPointerStress(Test* test) {
	runGpuHostPointerStress(test);
}

void checkGpuDeferredAllocationDeletionThresholdFlush(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	const size_t allocationCount = 192;
	const size_t allocationSize = 64 * 1024;

	void** allocations = (void**)malloc(sizeof(void*) * allocationCount);
	if (allocations == nullptr) {
		testOutOfMemory(test);
	}

	for (size_t i = 0; i < allocationCount; i++) {
		allocations[i] = gpuMalloc(allocationSize, 16, GPU_MEMORY_DEFAULT, &result);
		TEST_ASSERT(test, result == GPU_SUCCESS);
		TEST_ASSERT(test, allocations[i] != nullptr);
	}

	void* first = allocations[0];
	for (size_t i = 0; i < allocationCount; i++) {
		gpuFree(allocations[i]);
	}

	void* devicePtr = gpuHostToDevicePointer(first, &result);
	TEST_ASSERT(test, result == GPU_NO_SUCH_ALLOCATION_FOUND);
	TEST_ASSERT(test, devicePtr == nullptr);

	free(allocations);
	gpuDeinit();
}
