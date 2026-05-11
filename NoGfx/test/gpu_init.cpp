#include "gpu_common.h"

void checkGpuInitAndDeinit(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuDeinit();
}

void checkGpuInvalidBackend(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectUnavailableBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);

	TEST_ASSERT(test, result == GPU_BACKEND_NOT_SUPPORTED);

	gpuDeinit();
}

void checkGpuEnumerateDevices(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;

	gpuEnumerateDevices(&devices, &count, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, count > 0);
	TEST_ASSERT(test, devices != nullptr);

	gpuDeinit();
}

void checkGpuSelectDevice(Test* test) {
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

	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuDeinit();
}

void checkGpuSelectInvalidDevice(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuSelectDevice((GpuDeviceId)999999, &result);
	TEST_ASSERT(test, result == GPU_INVALID_DEVICE);

	gpuDeinit();
}

void checkGpuDoubleDeviceSelection(Test* test) {
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
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuSelectDevice(devices[0].identifier, &result);
	TEST_ASSERT(test, result == GPU_DEVICE_ALREADY_SELECTED);

	gpuDeinit();
}
