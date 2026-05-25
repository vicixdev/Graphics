#include <stdio.h>
#include <unistd.h>
#include <gpu/gpu.h>

#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image.h"
#include "stb_image_write.h"

GpuBackend selectBackend(void) {
	#ifdef __APPLE__
		return GPU_METAL_4;
	#else
		return GPU_VULKAN;
	#endif
}

typedef struct GpuAllocation {
	uint8_t*	cpu;
	uint8_t*	gpu;
} GpuAllocation;

typedef struct GpuBumpAllocator {
	uint8_t*	cpu;
	uint8_t*	gpu;
	uint32_t	size;
	uint32_t	offset;
} GpuBumpAllocator;

void createGpuBumpAllocator(GpuBumpAllocator* allocator, size_t size, GpuMemory memory) {
	allocator->cpu = (uint8_t*)gpuMalloc(size, 16, memory, NULL);
	allocator->gpu = (uint8_t*)gpuHostToDevicePointer(allocator->cpu, NULL);
	allocator->offset = 0;
	allocator->size = size;
}

GpuAllocation bumpAlloc(GpuBumpAllocator* allocator, size_t bytes) {
	if (allocator->offset + bytes >= allocator->size) {
		allocator->offset = 0;
	}

	GpuAllocation alloc;
	alloc.cpu = allocator->cpu + allocator->offset;
	alloc.gpu = allocator->gpu + allocator->offset;

	allocator->offset += bytes;

	return alloc;
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

	GpuBumpAllocator bumpAllocator;
	createGpuBumpAllocator(&bumpAllocator, 1 * 1024 * 1024, GPU_MEMORY_READBACK);

	GpuSemaphore semaphore = gpuCreateSemaphore(0, &result);
	if (result != GPU_SUCCESS) {
		printf("Could not create a semaphore. Aborting.\n");
		return -1;
	}

	FILE* f = fopen("image.png", "rb");
	if (f == NULL) {
		printf("Could not open image.png\n");
		gpuDeinit();
		return -1;
	}

	int x, y, channels;
	const int outputChannels = 4;
	uint8_t* data = stbi_load_from_file(f, &x, &y, &channels, outputChannels);
	assert(data != NULL);

	fclose(f);

	size_t imageSize = (size_t)x * (size_t)y * (size_t)outputChannels;
	GpuAllocation gpuTempData = bumpAlloc(&bumpAllocator, imageSize);
	memcpy(gpuTempData.cpu, data, imageSize);
	printf("STBI bytes: %02x %02x %02x %02x %02x %02x %02x %02x\n",
		data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7]);
	printf("Staging bytes: %02x %02x %02x %02x %02x %02x %02x %02x\n",
		gpuTempData.cpu[0], gpuTempData.cpu[1], gpuTempData.cpu[2], gpuTempData.cpu[3],
		gpuTempData.cpu[4], gpuTempData.cpu[5], gpuTempData.cpu[6], gpuTempData.cpu[7]);

	GpuTextureDesc textureDescriptor = {};
	textureDescriptor.type = GPU_TEXTURE_2D;
	textureDescriptor.format = GPU_FORMAT_RGBA8_UNORM;
	textureDescriptor.usage = GPU_USAGE_SAMPLED;
	textureDescriptor.dimensions[0] = x;
	textureDescriptor.dimensions[1] = y;
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

	void* gpuTexture2Buffer = gpuMalloc(sizeAlign.size + 1024, sizeAlign.align, GPU_MEMORY_GPU, NULL);
	GpuTexture texture2 = gpuCreateTexture(&textureDescriptor, gpuTexture2Buffer, &result);
	if (result != GPU_SUCCESS) {
		printf("Failed to create texture. Got error %d.\n", result);
		gpuDeinit();
		return -1;
	}

	GpuQueue queue = gpuCreateQueue(NULL);

	GpuCommandBuffer commandBuffer = gpuStartCommandEncoding(queue, NULL);
	GpuResult copyResult = GPU_SUCCESS;
	gpuCopyToTexture(commandBuffer, gpuTextureBuffer, gpuTempData.gpu, texture, &copyResult);
	if (copyResult != GPU_SUCCESS) {
		printf("gpuCopyToTexture failed with error %d.\n", copyResult);
	}
	gpuSubmitWithSignal(queue, &commandBuffer, 1, semaphore, 1, NULL);
	gpuWaitSemaphore(semaphore, 1, NULL);

	GpuAllocation downloadBuffer;
	downloadBuffer.cpu = (uint8_t*)gpuMalloc(imageSize, 16, GPU_MEMORY_READBACK, NULL);
	downloadBuffer.gpu = (uint8_t*)gpuHostToDevicePointer(downloadBuffer.cpu, NULL);

	commandBuffer = gpuStartCommandEncoding(queue, NULL);
	copyResult = GPU_SUCCESS;
	gpuMemCpy(commandBuffer, (uint8_t*)gpuTexture2Buffer, gpuTextureBuffer, sizeAlign.size, NULL);
	if (copyResult != GPU_SUCCESS) {
		printf("gpuCopyFromTexture failed with error %d.\n", copyResult);
	}
	gpuSubmitWithSignal(queue, &commandBuffer, 1, semaphore, 2, NULL);
	gpuWaitSemaphore(semaphore, 2, NULL);

	commandBuffer = gpuStartCommandEncoding(queue, NULL);
	copyResult = GPU_SUCCESS;
	gpuCopyFromTexture(commandBuffer, downloadBuffer.gpu, gpuTexture2Buffer, texture2, &copyResult);
	if (copyResult != GPU_SUCCESS) {
		printf("gpuCopyFromTexture failed with error %d.\n", copyResult);
	}
	gpuSubmitWithSignal(queue, &commandBuffer, 1, semaphore, 3, NULL);
	gpuWaitSemaphore(semaphore, 3, NULL);

	printf("Memcpy bytes: %02x %02x %02x %02x %02x %02x %02x %02x\n",
		downloadBuffer.cpu[0], downloadBuffer.cpu[1], downloadBuffer.cpu[2], downloadBuffer.cpu[3],
		downloadBuffer.cpu[4], downloadBuffer.cpu[5], downloadBuffer.cpu[6], downloadBuffer.cpu[7]);

	stbi_write_png("out.png", x, y, 4, downloadBuffer.cpu, x * 4);
	stbi_image_free(data);
	
	gpuDeinit();
	return 0;
}

