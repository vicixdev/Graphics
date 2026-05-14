#include <stdio.h>
#include <unistd.h>
#include <gpu/gpu.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define OUTPUT_WIDTH 640
#define OUTPUT_HEIGHT 480

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

	GpuSemaphore semaphore = gpuCreateSemaphore(0, &result);
	if (result != GPU_SUCCESS) {
		printf("Could not create a semaphore. Aborting.\n");
		return -1;
	}

	GpuTextureDesc textureDescriptor = {};
	textureDescriptor.type = GPU_TEXTURE_2D;
	textureDescriptor.format = GPU_FORMAT_RGBA8_UNORM;
	textureDescriptor.usage = GPU_USAGE_COLOR_ATTACHMENT;
	textureDescriptor.dimensions[0] = OUTPUT_WIDTH;
	textureDescriptor.dimensions[1] = OUTPUT_HEIGHT;
	textureDescriptor.dimensions[2] = 1;
	textureDescriptor.layerCount = 1;
	textureDescriptor.mipCount = 1;
	textureDescriptor.sampleCount = 1;

	GpuTextureSizeAlign sizeAlign = gpuTextureSizeAlign(&textureDescriptor, NULL);

	void* gpuTextureBuffer = gpuMalloc(sizeAlign.size + 1024, sizeAlign.align, GPU_MEMORY_GPU, NULL);
	GpuTexture texture = gpuCreateTexture(&textureDescriptor, gpuTextureBuffer, &result);
	if (result != GPU_SUCCESS) {
		printf("Failed to create texture. Got error %d.\n", result);
		gpuDeinit();
		return -1;
	}

	uint8_t* downloadBuffer = (uint8_t*)gpuMalloc(OUTPUT_WIDTH * OUTPUT_HEIGHT * 4, 0, GPU_MEMORY_READBACK, NULL);
	void* deviceDownloadBuffer = gpuHostToDevicePointer(downloadBuffer, NULL);

	GpuQueue queue = gpuCreateQueue(NULL);

	GpuRenderTarget renderTarget = {};
	renderTarget.texture = texture;
	renderTarget.clearColor[0] = 0.0f;
	renderTarget.clearColor[1] = 1.0f;
	renderTarget.clearColor[2] = 0.0f;
	renderTarget.clearColor[3] = 1.0f;
	renderTarget.loadOp = GPU_OP_CLEAR;
	renderTarget.storeOp = GPU_OP_STORE;

	GpuRenderPassDesc renderPass = {};
	renderPass.colorTargetCount = 1;
	renderPass.colorTargets = &renderTarget;

	GpuCommandBuffer commandBuffer = gpuStartCommandEncoding(queue, NULL);
	gpuBeginRenderPass(commandBuffer, &renderPass, NULL);
	gpuEndRenderPass(commandBuffer, NULL);
	gpuSubmitWithSignal(queue, &commandBuffer, 1, semaphore, 1, NULL);

	gpuWaitSemaphore(semaphore, 1, NULL);

	commandBuffer = gpuStartCommandEncoding(queue, NULL);
	gpuCopyFromTexture(commandBuffer, deviceDownloadBuffer, gpuTextureBuffer, texture, NULL);
	gpuSubmitWithSignal(queue, &commandBuffer, 1, semaphore, 2, NULL);

	gpuWaitSemaphore(semaphore, 2, NULL);

	stbi_write_png("out.png", OUTPUT_WIDTH, OUTPUT_HEIGHT, 4, downloadBuffer, OUTPUT_WIDTH * 4);
	
	gpuDeinit();
	return 0;
}

