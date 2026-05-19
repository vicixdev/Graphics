#include "context.h"

#include <stdlib.h>

#include <lib/common/type_traits.h>
#include <lib/common/scoped_nsautoreleasepool.h>
#include <lib/metal4/device.h>
#include <lib/metal4/allocation.h>
#include <lib/metal4/textures.h>
#include <lib/metal4/queue.h>
#include <lib/metal4/command_buffers.h>
#include <lib/metal4/semaphores.h>
#include <lib/metal4/deletion_manager.h>
#include <lib/metal4/shader/acquire_icb_range.h>
#include <lib/metal4/shader/prep_multidrawindirect.h>

// 128 KB
#define MTL4_GLOBAL_MEMORY 128 * 1024

// 1 MB
#define MTL4_TEMP_MEMORY 1 * 1024 * 1024

static const uint32_t MTL4_ACQUIRE_ICB_RANGE_CONSTANTS[1] = {
	/*icbBufferSize=*/	MTL4_MAX_MULTIDRAW_ARG_COUNT * MTL4_MAX_MULTIDRAW_CALLS,
};
static uint32_t MTL4_ACQUIRE_ICB_RANGE_GROUP_SIZE[3] = { 1, 1, 1 };

static uint32_t MTL4_PREPARE_MULTIDRAW_ICBS_GROUP_SIZE[3] = { 64, 1, 1 };


Mtl4Context gMtl4Context;

void mtl4Init(const GpuInitDesc* desc, GpuResult* result) {
	CmnScopedNSAutoreleasePool pool;

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

	mtl4InitQueueStorage(&localResult);
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
	CmnScopedNSAutoreleasePool pool;

	if (gMtl4Context.isCurrentlyTracing) {
		mtl4StopTracing();
	}

	mtl4FreePipeline(mtl4HandleToGpuPipeline(gMtl4Context.acquireIcbRange));
	mtl4FreePipeline(mtl4HandleToGpuPipeline(gMtl4Context.prepareMultidrawIcbs));

	mtl4DeleteScheduledPipelines();
	mtl4DeleteScheduledTextures();
	mtl4DeleteScheduledAllocations();

	mtl4FiniCommandBufferStorage();
	mtl4FiniSemaphoreStorage();
	mtl4FiniQueueStorage();
	mtl4FiniCommandBufferStorage();
	mtl4FiniPipelineStorage();
	mtl4FiniTextureStorage();
	mtl4FiniAllocationStorage();
	mtl4FiniDeletionManager();

	if (gMtl4Context.zeroBuffer != nil) {
		[gMtl4Context.zeroBuffer release];
	}

	if (gMtl4Context.residencySet != nil) {
		[gMtl4Context.residencySet release];
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

void mtl4AddAllocationToResidencySet(id<MTLAllocation> allocation) {
	if (allocation == nil) {
		return;
	}

	CmnScopedMutex guard(&gMtl4Context.residencySetMutex);
	[gMtl4Context.residencySet addAllocation:allocation];
}

void mtl4RemoveAllocationToResidencySet(id<MTLAllocation> allocation) {
	if (allocation == nil) {
		return;
	}

	CmnScopedMutex guard(&gMtl4Context.residencySetMutex);
	[gMtl4Context.residencySet removeAllocation:allocation];
}

void mtl4PrepareContextWithDevice(GpuDeviceId deviceId, GpuResult* result) {

	// This is a non-owning pointer. Ownership is held by availableDevices.devices.
	gMtl4Context.device = gMtl4Context.availableDevices.devices[deviceId];
	gMtl4Context.selectedDeviceId = deviceId;


	MTLResidencySetDescriptor* residencySetDescriptor = [MTLResidencySetDescriptor new];
	defer ([residencySetDescriptor release]);

	gMtl4Context.residencySet = [gMtl4Context.device
		newResidencySetWithDescriptor:residencySetDescriptor error:nil];
	if (gMtl4Context.residencySet == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
	}


	gMtl4Context.zeroBuffer = [gMtl4Context.device
		newBufferWithLength:1024
		options:MTLResourceStorageModePrivate
	];
	if (gMtl4Context.zeroBuffer == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
	}
	gMtl4Context.zeroBuffer.label = @"gMtl4Context.zeroBuffer";
	mtl4AddAllocationToResidencySet(gMtl4Context.zeroBuffer);

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4PrepareBuiltinPipelines(GpuResult* result) {
	GpuResult localResult;

	GpuPipeline acquireIcbRange = gpuCreateComputePipeline(
		gMtl4AcquireIcbRangeBytecode, sizeof(gMtl4AcquireIcbRangeBytecode),
		MTL4_ACQUIRE_ICB_RANGE_CONSTANTS, sizeof(MTL4_ACQUIRE_ICB_RANGE_CONSTANTS),
		MTL4_ACQUIRE_ICB_RANGE_GROUP_SIZE,
		&localResult);
	assert(localResult == GPU_SUCCESS && "The builtin `acquireIcbRange` pipeline failed to compile.");
	gMtl4Context.acquireIcbRange = mtl4GpuPipelineToHandle(acquireIcbRange);

	GpuPipeline prepareMultiDrawIcbs = gpuCreateComputePipeline(
		gMtl4PrepareMultidrawIndirectIcbsBytecode, sizeof(gMtl4PrepareMultidrawIndirectIcbsBytecode),
		NULL, 0,
		MTL4_PREPARE_MULTIDRAW_ICBS_GROUP_SIZE,
		&localResult);
	assert(localResult == GPU_SUCCESS && "The builtin `prepareMultidrawIndirectIcbs` pipeline failed to compile.");
	gMtl4Context.prepareMultidrawIcbs = mtl4GpuPipelineToHandle(prepareMultiDrawIcbs);

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

