#include "gpu_common.h"

void gpuTestSignalWritingOnGpuPtr(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
	}

	void* signalMemory = gpuMalloc(sizeof(uint64_t), 0, GPU_MEMORY_DEFAULT, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	void* gpuSignalMemory = gpuHostToDevicePointer(signalMemory, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	*(uint64_t*)signalMemory = 0;

	GpuQueue queue = gpuCreateQueue(&result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuSemaphore semaphore = gpuCreateSemaphore(0, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuCommandBuffer commandBuffer = gpuStartCommandEncoding(queue, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuMemCpy(commandBuffer, gpuSignalMemory, gpuSignalMemory, sizeof(uint64_t), &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuSignalAfter(commandBuffer, GPU_STAGE_TRANSFER, gpuSignalMemory, 1, GPU_SIGNAL_ATOMIC_MAX, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuWaitBefore(commandBuffer, GPU_STAGE_TRANSFER, gpuSignalMemory, 1, GPU_OP_GREATER_EQUAL, GPU_HAZARD_NONE, -1, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuSubmitWithSignal(queue, &commandBuffer, 1, semaphore, 1, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuWaitSemaphore(semaphore, 1, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	TEST_ASSERT(test, *(uint64_t*)signalMemory == 1);
}
