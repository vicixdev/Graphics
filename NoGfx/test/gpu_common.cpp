#include "gpu_common.h"

#include <cstdio>
#include <cstdlib>

GpuBackend selectBackendForCurrentPlatform(void) {
	#ifdef __APPLE__
		return GPU_METAL_4;
	#else
		return GPU_NONE;
	#endif
}

GpuBackend selectUnavailableBackendForCurrentPlatform(void) {
	#ifdef __APPLE__
		return GPU_VULKAN;
	#else
		return GPU_METAL_4;
	#endif
}

GpuTextureDesc makeDefaultTextureDesc(void) {
	GpuTextureDesc desc = {};
	desc.type = GPU_TEXTURE_2D;
	desc.dimensions[0] = 64;
	desc.dimensions[1] = 64;
	desc.dimensions[2] = 1;
	desc.mipCount = 1;
	desc.layerCount = 1;
	desc.sampleCount = 1;
	desc.format = GPU_FORMAT_RGBA8_UNORM;
	desc.usage = GPU_USAGE_SAMPLED;

	return desc;
}

bool initGpuAndSelectFirstDevice(GpuResult* result) {
	GpuInitDesc initDesc = {};
	initDesc.backend = selectBackendForCurrentPlatform();
	initDesc.validationEnabled = true;

	gpuInit(&initDesc, result);
	if (*result != GPU_SUCCESS) {
		return false;
	}

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, result);
	if (*result != GPU_SUCCESS || count == 0 || devices == nullptr) {
		gpuDeinit();
		return false;
	}

	gpuSelectDevice(devices[0].identifier, result);
	if (*result != GPU_SUCCESS) {
		gpuDeinit();
		return false;
	}

	return true;
}

bool loadBinaryFile(const char* path, uint8_t** data, size_t* size) {
	FILE* file = fopen(path, "rb");
	if (file == nullptr) {
		return false;
	}

	if (fseek(file, 0, SEEK_END) != 0) {
		fclose(file);
		return false;
	}

	long fileSize = ftell(file);
	if (fileSize <= 0) {
		fclose(file);
		return false;
	}

	if (fseek(file, 0, SEEK_SET) != 0) {
		fclose(file);
		return false;
	}

	uint8_t* buffer = (uint8_t*)malloc((size_t)fileSize);
	if (buffer == nullptr) {
		fclose(file);
		return false;
	}

	size_t readSize = fread(buffer, 1, (size_t)fileSize, file);
	fclose(file);
	if (readSize != (size_t)fileSize) {
		free(buffer);
		return false;
	}

	*data = buffer;
	*size = (size_t)fileSize;
	return true;
}

void freeBinaryFile(uint8_t* data) {
	free(data);
}


