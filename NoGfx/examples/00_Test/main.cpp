#include <stdio.h>
#include <gpu/gpu.h>

GpuBackend selectBackend(void) {
	#ifdef __APPLE__
		return GPU_METAL_4;
	#else
		return GPU_VULKAN;
	#endif
}

// extern "C" void __Z10mtl4Deinitv(void);
extern void mtl4Deinit(void);

int main(void) {
	GpuInitDesc desc;
	desc.backend		= selectBackend();
	desc.validationEnabled	= true;
	desc.tracingEnabled	= true;
	desc.extraLayers	= NULL;
	desc.extraLayerCount	= 0;

	GpuResult result = GPU_SUCCESS;

	mtl4Deinit();

	gpuInit(&desc, &result);
	if (result != GPU_SUCCESS) {
		printf("Failed to initalize NoGfx. Got error %d.\n", result);
		return -1;
	}

	GpuDeviceInfo* devices;
	size_t devices_count;
	gpuEnumerateDevices(&devices, &devices_count, &result);
	if (result != GPU_SUCCESS) {
		printf("Failed to get the available devices. Got error %d.\n", result);
		return -1;
	}

	printf("Available devices:\n");
	for (size_t i = 0; i < devices_count; i++) {
		GpuDeviceInfo* info = &devices[i];

		printf(
			"\t%u - %s (%s - %s)\n",
			(unsigned int)info->identifier,
			info->name,
			info->vendor,
			info->type == GPU_INTEGRATED ? "Integrated" : "Dedicated"
		);
	}

	if (devices_count <= 0) {
		printf("No available devices found. Aborting.\n");
		return -1;
	}

	gpuSelectDevice(devices[0].identifier, &result);
	if (result != GPU_SUCCESS) {
		printf("Could not select a the specified device. Aborting.\n");
		return -1;
	}
	printf("Using device `%s`.\n", devices[0].name);

	void* signalMemory = gpuMalloc(sizeof(uint64_t), 0, GPU_MEMORY_DEFAULT, NULL);
	*(uint64_t*)signalMemory = 0;

	void* gpuSignalMemory = gpuHostToDevicePointer(signalMemory, NULL);
	printf("CPU address: %p, GPU address: %p\n", signalMemory, gpuSignalMemory);

	GpuQueue queue = gpuCreateQueue(NULL);
	GpuSemaphore semaphore = gpuCreateSemaphore(0, NULL);

	GpuCommandBuffer commandBuffer = gpuStartCommandEncoding(queue, NULL);

	// gpuMemCpy(commandBuffer, gpuSignalMemory, gpuSignalMemory, sizeof(uint64_t), NULL);
	GpuResult signalResult = GPU_SUCCESS;
	gpuSignalAfter(commandBuffer, GPU_STAGE_TRANSFER, gpuSignalMemory, 1, GPU_SIGNAL_ATOMIC_SET, &signalResult);
	if (signalResult != GPU_SUCCESS) {
		printf("Signal failed with error %d\n", signalResult);
	}

	GpuResult waitResult = GPU_SUCCESS;
	gpuWaitBefore(commandBuffer, GPU_STAGE_TRANSFER, gpuSignalMemory, 1, GPU_OP_EQUAL, GPU_HAZARD_NONE, -1, &waitResult);
	if (waitResult != GPU_SUCCESS) {
		printf("Wait failed with error %d\n", waitResult);
	}

	printf("Before submit: value = %llu\n", *(uint64_t*)signalMemory);
	
	GpuResult submitResult = GPU_SUCCESS;
	gpuSubmitWithSignal(queue, &commandBuffer, 1, semaphore, 1, &submitResult);
	if (submitResult != GPU_SUCCESS) {
		printf("Submit failed with error %d\n", submitResult);
	}

	gpuWaitSemaphore(semaphore, 1, NULL);

	printf("After wait: value = %llu\n", *(uint64_t*)signalMemory);
	printf("%llu\n", *(uint64_t*)signalMemory);

	return 0;
}


