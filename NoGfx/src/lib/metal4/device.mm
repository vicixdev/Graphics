#include "device.h"

#include <lib/metal4/context.h>
#include <lib/metal4/allocation.h>
#include <lib/metal4/pipelines.h>
#include <lib/metal4/command_buffers.h>
#include <lib/metal4/events.h>

static const GpuSignal gMtl4SupportedSignals[] = { GPU_SIGNAL_ATOMIC_MAX };
static const GpuOp gMtl4SupportedWaitOps[] = { GPU_OP_GREATER_EQUAL };

static const GpuDeviceCapabilites gMtl4CommonDeviceCapabilites = {
	/*supportedSignals=*/		&gMtl4SupportedSignals[0],
	/*supportedSignalCount=*/	CMN_COUNT_OF(gMtl4SupportedSignals),
	/*supportedWaitOps=*/		&gMtl4SupportedWaitOps[0],
	/*supportedWaitOpCount=*/	CMN_COUNT_OF(gMtl4SupportedWaitOps),
	/*supportsArbitraryWaitMask=*/	false,
	/*gpuReadableSignals=*/		true,
	/*gpuWritableSignals=*/		false,
};

bool mtl4CheckDeviceSuitability(id<MTLDevice> device) {
	return device.hasUnifiedMemory &&
		[device supportsFamily:MTLGPUFamilyMetal4];
}

void mtl4PrepareAvailableDevicesList(GpuResult* result) {
	CmnArena* arena = &gMtl4Context.globalArena;
	CmnArenaState onErrorRecoveryState = cmnBeginArenaTemp(arena);

	NSArray<id<MTLDevice>>* mtlDevices = MTLCopyAllDevices();

	GpuDeviceInfo* devicesInfo = cmnArenaAlloc<GpuDeviceInfo>(arena, mtlDevices.count, nullptr);
	if (devicesInfo == nullptr) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		goto on_error_cleanup;
	}
	id<MTLDevice>* suitableMtlDevices; suitableMtlDevices = cmnArenaAlloc<id<MTLDevice>>(arena, mtlDevices.count, nullptr);
	if (suitableMtlDevices == nullptr) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		goto on_error_cleanup;
	}

	GpuDeviceId deviceId; deviceId = 0;

	for (size_t i = 0; i < [mtlDevices count]; i++) {
		id<MTLDevice> mtlDevice = mtlDevices[i];
		GpuDeviceInfo* deviceInfo = &devicesInfo[deviceId];

		if (!mtl4CheckDeviceSuitability(mtlDevice)) {
			continue;
		}

		size_t deviceNameLength = [mtlDevice.name maximumLengthOfBytesUsingEncoding:NSUTF8StringEncoding];
		deviceInfo->name = cmnArenaAlloc<char>(arena, deviceNameLength, 0, NULL);
		if (deviceInfo->name == nullptr) {
			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			goto on_error_cleanup;
		}
		[mtlDevice.name
			getCString:(char*)deviceInfo->name
			maxLength:deviceNameLength
			encoding:NSUTF8StringEncoding];

		// TODO: Actually check for other types of vendor. This should be fine, since only Apple hardware is
		//	supported.
		deviceInfo->vendor = "Apple";
		deviceInfo->identifier = deviceId;
		// TODO: Apple describes the M-series GPUs as high power, even if they are integrated :*(
		deviceInfo->type = mtlDevice.isLowPower ? GPU_INTEGRATED : GPU_DEDICATED;

		deviceInfo->capabilities = gMtl4CommonDeviceCapabilites;

		// Keep an owned reference so the device remains valid after the temporary NSArray is released.
		suitableMtlDevices[deviceId] = [mtlDevice retain];

		deviceId++;
	}

	gMtl4Context.availableDevices.info = devicesInfo;
	gMtl4Context.availableDevices.devices = suitableMtlDevices;
	gMtl4Context.availableDevices.count = deviceId;

	[mtlDevices release];

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;

on_error_cleanup:
	gMtl4Context.availableDevices.info = nullptr;
	gMtl4Context.availableDevices.count = 0;

	cmnEndArenaTemp(onErrorRecoveryState);
	[mtlDevices release];
}

void mtl4EnumerateDevices(GpuDeviceInfo** devices, size_t* devices_count, GpuResult* result) {
	*devices = gMtl4Context.availableDevices.info;
	*devices_count = gMtl4Context.availableDevices.count;

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4SelectDevice(GpuDeviceId deviceId, GpuResult* result) {

	GpuResult localResult;

	mtl4PrepareContextWithDevice(deviceId, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}

	mtl4InitPipelineStorage(&localResult);
	if (localResult != GPU_SUCCESS) {
		mtl4FiniPipelineStorage();

		CMN_SET_RESULT(result, localResult);
		return;
	}

	mtl4PrepareBuiltinPipelines(&localResult);
	if (localResult != GPU_SUCCESS) {
		mtl4FiniPipelineStorage();

		CMN_SET_RESULT(result, localResult);
		return;
	}

	mtl4InitEventStorage(&localResult);
	if (localResult != GPU_SUCCESS) {
		mtl4FiniPipelineStorage();
		mtl4FiniEventStorage();

		CMN_SET_RESULT(result, localResult);
		return;
	}

	mtl4InitCommandBufferStorage(&localResult);
	if (localResult != GPU_SUCCESS) {
		mtl4FiniPipelineStorage();
		mtl4FiniEventStorage();
		mtl4FiniCommandBufferStorage();

		CMN_SET_RESULT(result, localResult);
		return;
	}

	if (gMtl4Context.shouldTrace) {
		mtl4BeginTracing("/tmp/nogfx.gputrace");
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

bool mtl4HasDevice(void) {
	return gMtl4Context.device != nil;
}

void mtl4BeginTracing(const char* traceDestinationFile) {
	MTLCaptureManager* captureManager = [MTLCaptureManager sharedCaptureManager];
	if (![captureManager supportsDestination:MTLCaptureDestinationGPUTraceDocument]) {
		printf(
			"WARN - Could not start a capture. Try starting the application with the following "
			"environment variables:\n"
			"\t- MTL_DEBUG_LAYER=1\n"
			"\t- MTL_CAPTURE_ENABLED=1\n"
		);
		return;
	}

	MTLCaptureDescriptor* captureDescriptor = [MTLCaptureDescriptor new];
	defer ([captureDescriptor release]);

	captureDescriptor.captureObject = gMtl4Context.device;
	captureDescriptor.destination = MTLCaptureDestinationGPUTraceDocument;
	captureDescriptor.outputURL = [NSURL fileURLWithPath: (NSString*)__CFStringMakeConstantString(traceDestinationFile)];

	if (access("/tmp/nogfx.gputrace", F_OK) == 0) {
		// NOTE: Removing a folder with the C standard library is difficult.
		system("rm -rf /tmp/nogfx.gputrace");
	}

	NSError* err = nil;
	[captureManager startCaptureWithDescriptor:captureDescriptor error:&err];
	if (err != nil) {
		printf("WARN - Could not start a capture:\n");
		printf("\t%s\n", [[err localizedFailureReason] UTF8String]);
		printf("\t%s\n", [[err localizedDescription] UTF8String]);
	}

	gMtl4Context.isCurrentlyTracing = true;
}

void mtl4StopTracing(void) {
	if (!gMtl4Context.isCurrentlyTracing) {
		return;
	}

	MTLCaptureManager* captureManager = [MTLCaptureManager sharedCaptureManager];
	[captureManager stopCapture];
}

