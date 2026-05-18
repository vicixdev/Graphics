#include "context.h"

#include <stdlib.h>

#include <lib/common/type_traits.h>
#include <lib/metal4/device.h>
#include <lib/metal4/allocation.h>
#include <lib/metal4/textures.h>
#include <lib/metal4/queue.h>
#include <lib/metal4/command_buffers.h>
#include <lib/metal4/semaphores.h>
#include <lib/metal4/deletion_manager.h>

// 128 KB
#define MTL4_GLOBAL_MEMORY 128 * 1024

// 1 MB
#define MTL4_TEMP_MEMORY 1 * 1024 * 1024

Mtl4Context gMtl4Context;

void mtl4Init(const GpuInitDesc* desc, GpuResult* result) {
	GpuResult localResult;

	gMtl4Context.shouldTrace = desc->tracingEnabled;

	gMtl4Context.globalBackingMemory	= (uint8_t*)malloc(MTL4_GLOBAL_MEMORY);
	if (gMtl4Context.globalBackingMemory == nullptr) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		goto on_error_cleanup;
	}

	gMtl4Context.tempBackingMemory		= (uint8_t*)malloc(MTL4_TEMP_MEMORY);
	if (gMtl4Context.tempBackingMemory == nullptr) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		goto on_error_cleanup;
	}

	gMtl4Context.globalArena	= cmnCreateArena(gMtl4Context.globalBackingMemory, MTL4_GLOBAL_MEMORY, true);
	gMtl4Context.tempArena		= cmnCreateArena(gMtl4Context.tempBackingMemory, MTL4_TEMP_MEMORY, true);

	mtl4PrepareAvailableDevicesList(&localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		goto on_error_cleanup;
	}

	mtl4InitAllocationStorage(&localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		goto on_error_cleanup;
	}

	mtl4InitTextureStorage(&localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		goto on_error_cleanup;
	}

	mtl4InitSemaphoreStorage(&localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		goto on_error_cleanup;
	}

	mtl4InitDeletionManager(&localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		goto on_error_cleanup;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;

on_error_cleanup:
	mtl4Deinit();
	return;
}

void mtl4Deinit(void) {
	mtl4DeleteScheduledPipelines();
	mtl4DeleteScheduledTextures();
	mtl4DeleteScheduledAllocations();

	mtl4FiniCommandEmissionStorage();
	mtl4FiniCommandBufferStorage();
	mtl4FiniSemaphoreStorage();
	mtl4FiniCommandBufferStorage();
	mtl4FiniPipelineStorage();
	mtl4FiniTextureStorage();
	mtl4FiniAllocationStorage();
	mtl4FiniDeletionManager();

	if (gMtl4Context.isCurrentlyTracing) {
		mtl4StopTracing();
	}

	if (gMtl4Context.availableDevices.devices != nullptr) {
		for (size_t i = 0; i < gMtl4Context.availableDevices.count; i++) {
			id<MTLDevice> device = gMtl4Context.availableDevices.devices[i];
			if (device != nil) {
				[device release];
			}
		}
	}

	free(gMtl4Context.globalBackingMemory);
	free(gMtl4Context.tempBackingMemory);

	gMtl4Context = {};
}

