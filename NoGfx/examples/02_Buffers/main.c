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

	
	float data[8] = { 0, 1, 2, 3, 4, 5, 6, 7 };

	void* privateBuffer		= gpuMalloc(sizeof(data), 4, GPU_MEMORY_GPU, NULL);
	void* uploadBuffer		= gpuMalloc(sizeof(data), 4, GPU_MEMORY_DEFAULT, NULL);
	void* downloadBuffer		= gpuMalloc(sizeof(data), 4, GPU_MEMORY_READBACK, NULL);

	void* deviceUploadBuffer	= gpuHostToDevicePointer(uploadBuffer, NULL);
	void* deviceDownloadBuffer	= gpuHostToDevicePointer(downloadBuffer, NULL);

	printf("Private buffer GPU address: %lx\n", (uintptr_t)privateBuffer);
	printf("Upload buffer GPU address: %lx\n", (uintptr_t)deviceUploadBuffer);
	printf("Download buffer GPU address: %lx\n", (uintptr_t)deviceDownloadBuffer);

	memcpy(uploadBuffer, data, sizeof(data));
	
	GpuQueue queue = gpuCreateQueue(NULL);
	GpuSemaphore semaphore = gpuCreateSemaphore(0, NULL);

	GpuCommandBuffer commandBuffer = gpuStartCommandEncoding(queue, NULL);

	gpuMemCpy(commandBuffer, privateBuffer, deviceUploadBuffer, sizeof(data), NULL);
	gpuBarrier(commandBuffer, GPU_STAGE_TRANSFER, GPU_STAGE_TRANSFER, GPU_HAZARD_NONE, NULL);
	gpuMemCpy(commandBuffer, privateBuffer, (float*)privateBuffer + 4, sizeof(float), NULL);
	gpuBarrier(commandBuffer, GPU_STAGE_TRANSFER, GPU_STAGE_TRANSFER, GPU_HAZARD_NONE, NULL);
	gpuMemCpy(commandBuffer, deviceDownloadBuffer, privateBuffer, sizeof(data), NULL);

	gpuSubmitWithSignal(queue, &commandBuffer, 1, semaphore, 1, NULL);
	gpuWaitSemaphore(semaphore, 1, NULL);

	printf("Downloaded data: ");
	for (size_t i = 0; i < sizeof(data) / sizeof(*data); i++) {
		printf("%f ", ((float*)downloadBuffer)[i]);
	}
	printf("\n");

	gpuDeinit();
	return 0;
}

