#include <stdio.h>
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

	// TODO: Figure out what to do

	gpuDeinit();
	return 0;
}

