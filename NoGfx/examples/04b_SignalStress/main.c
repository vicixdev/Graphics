#include <stdio.h>
#include <string.h>
#include <gpu/gpu.h>

GpuBackend selectBackend(void) {
	#ifdef __APPLE__
		return GPU_METAL_4;
	#else
		return GPU_VULKAN;
	#endif
}

int main(void) {
	GpuInitDesc desc;
	desc.backend		= selectBackend();
	desc.validationEnabled	= true;
	desc.tracingEnabled	= true;
	desc.extraLayers	= NULL;
	desc.extraLayerCount	= 0;

	GpuResult result = GPU_SUCCESS;

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

	
	void* signal		= gpuMalloc(sizeof(uint64_t), 4, GPU_MEMORY_DEFAULT, NULL);
	void* deviceSignal	= gpuHostToDevicePointer(signal, NULL);

	GpuQueue queue = gpuCreateQueue(NULL);
	GpuSemaphore semaphore = gpuCreateSemaphore(0, NULL);

	GpuCommandBuffer commandBuffer = gpuStartCommandEncoding(queue, NULL);
	GpuCommandBuffer commandBuffer2 = gpuStartCommandEncoding(queue, NULL);

	for (size_t i = 0; i < 2; i++) {
		gpuSignalAfter(commandBuffer, (GpuStage)GPU_STAGES_ALL, deviceSignal, i, GPU_SIGNAL_ATOMIC_SET, NULL);
		gpuWaitBefore(commandBuffer2, (GpuStage)GPU_STAGES_ALL, deviceSignal, i, GPU_OP_LESS_EQUAL, GPU_HAZARD_NONE, GPU_DEFAULT_WAIT_MASK, NULL);
	}

	// The order does not change the behaviour...
	// GpuCommandBuffer commandBuffers[2] = { commandBuffer, commandBuffer2 };
	GpuCommandBuffer commandBuffers[2] = {commandBuffer2, commandBuffer};
	gpuSubmitWithSignal(queue, commandBuffers, 2, semaphore, 1, NULL);

	gpuWaitSemaphore(semaphore, 1, NULL);

	printf("Downloaded data: ");
	// for (size_t i = 0; i < sizeof(data) / sizeof(*data); i++) {
		// printf("%f ", ((float*)downloadBuffer)[i]);
	// }
	printf("\n");

	uint64_t signalValue = *(uint64_t*)signal;
	float signalValueF = *(float*)signal;
	printf("Signal: %llu %f\n", signalValue, signalValueF);
		
	gpuDeinit();
	return 0;
}

