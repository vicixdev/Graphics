#include "events.h"

#include <lib/common/heap_allocator.h>
#include <lib/metal4/command_buffers.h>
#include <lib/metal4/context.h>
#include <lib/metal4/allocation.h>

#include <lib/metal4/shaders/wait.h>
#include <lib/metal4/shaders/signal.h>

typedef struct Mtl4WaitOperation {
	uintptr_t	address;
	uint64_t	mask;
	uint64_t	value;
} Mtl4WaitOperation;

struct Mtl4SignalOperation {
	uintptr_t	address;
	uint64_t	value;
};

Mtl4EventStorage gMtl4EventStorage;

void mtl4InitEventStorage(GpuResult* result) {
	GpuResult localGpuResult;

	gMtl4EventStorage = {};

	gMtl4EventStorage.signaledValuesUploadBuffer = (uint64_t*)gpuMalloc(1024 * 1024, 0, GPU_MEMORY_DEFAULT, &localGpuResult);
	if (localGpuResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localGpuResult);
		return;
	}
	gMtl4EventStorage.uploadBufferSize = 1024 * 1024;
	gMtl4EventStorage.uploadBufferUsed = 0;

	gMtl4EventStorage.signaledValuesGpuBuffer = gpuHostToDevicePointer(gMtl4EventStorage.signaledValuesUploadBuffer, &localGpuResult);
	assert(localGpuResult == GPU_SUCCESS);

	MTLResidencySetDescriptor* residencySetDescriptor = [MTLResidencySetDescriptor new];
	defer ([residencySetDescriptor release]);
	residencySetDescriptor.initialCapacity = 1;
	residencySetDescriptor.label = @"Signaled values upload residency set";

	if (gMtl4EventStorage.signaledValuesUploadBuffer == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
	}

	for (size_t op = 0; op <= GPU_OP_ALWAYS; op++) {
		uint64_t constant = (uint64_t)op;

		gMtl4EventStorage.waitPipelines[op] = gpuCreateComputePipeline(
			gMtl4WaitKernelLib,
			sizeof(gMtl4WaitKernelLib),
			&constant,
			sizeof(uint64_t),
			&localGpuResult
		);
		assert(localGpuResult == GPU_SUCCESS && "The default shaders should be able to compile");
	}

	for (size_t signal = 0; signal <= GPU_SIGNAL_ATOMIC_OR; signal++) {
		uint64_t constant = (uint64_t)signal;

		gMtl4EventStorage.signalPipelines[signal] = gpuCreateComputePipeline(
			gMtl4SignalKernelLib,
			sizeof(gMtl4SignalKernelLib),
			&constant,
			sizeof(uint64_t),
			&localGpuResult
		);
		assert(localGpuResult == GPU_SUCCESS && "The default shaders should be able to compile");
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4FiniEventStorage() {
	gMtl4EventStorage = {};
}

size_t mtl4UploadFenceValue(uint64_t value) {
	uintptr_t values = (uintptr_t)gMtl4EventStorage.signaledValuesUploadBuffer;

	size_t valueOffset;
	for (;;) {
		valueOffset = cmnAtomicLoad(&gMtl4EventStorage.uploadBufferUsed);
		if (valueOffset >= gMtl4EventStorage.uploadBufferSize) {
			valueOffset = 0;
		}

		if (cmnAtomicCompareExchangeStrong<size_t>(
			&gMtl4EventStorage.uploadBufferUsed,
			valueOffset,
			valueOffset + sizeof(uint64_t)
		)) {
			break;
		}
	}

	uint64_t* valuePtr = (uint64_t*)(values + valueOffset);
	*valuePtr = value;

	return valueOffset;
}

void* mtl4UploadFenceWaitOp(Mtl4WaitOperation waitOp) {
	uintptr_t values = (uintptr_t)gMtl4EventStorage.signaledValuesUploadBuffer;

	size_t valueOffset;
	for (;;) {
		valueOffset = cmnAtomicLoad(&gMtl4EventStorage.uploadBufferUsed);
		if (valueOffset >= gMtl4EventStorage.uploadBufferSize) {
			valueOffset = 0;
		}

		if (cmnAtomicCompareExchangeStrong<size_t>(
			&gMtl4EventStorage.uploadBufferUsed,
			valueOffset,
			valueOffset + sizeof(Mtl4WaitOperation)
		)) {
			break;
		}
	}

	Mtl4WaitOperation* valuePtr = (Mtl4WaitOperation*)(values + valueOffset);
	*valuePtr = waitOp;

	return (void*)((uintptr_t)gMtl4EventStorage.signaledValuesGpuBuffer + valueOffset);
}

void* mtl4UploadFenceSignalOp(Mtl4SignalOperation signalOp) {
	uintptr_t values = (uintptr_t)gMtl4EventStorage.signaledValuesUploadBuffer;

	size_t valueOffset;
	for (;;) {
		valueOffset = cmnAtomicLoad(&gMtl4EventStorage.uploadBufferUsed);
		if (valueOffset >= gMtl4EventStorage.uploadBufferSize) {
			valueOffset = 0;
		}

		if (cmnAtomicCompareExchangeStrong<size_t>(
			&gMtl4EventStorage.uploadBufferUsed,
			valueOffset,
			valueOffset + sizeof(Mtl4SignalOperation)
		)) {
			break;
		}
	}

	Mtl4SignalOperation* valuePtr = (Mtl4SignalOperation*)(values + valueOffset);
	*valuePtr = signalOp;

	return (void*)((uintptr_t)gMtl4EventStorage.signaledValuesGpuBuffer + valueOffset);
}

void mtl4SignalEvent(
	GpuCommandBuffer commandBuffer,
	GpuStage after,
	GpuSignal signal,
	void* gpuPtr,
	uint64_t value,
	GpuResult* result
) {
	(void)after;

	Mtl4SignalOperation op;
	op.address	= (uintptr_t)gpuPtr;
	op.value	= value;
	
	void* signalOp = mtl4UploadFenceSignalOp(op);

	uint32_t gridDimentions[3] = { 1, 1, 1 };
	mtl4Barrier(commandBuffer, (GpuStage)GPU_STAGES_ALL, (GpuStage)GPU_STAGE_COMPUTE, GPU_HAZARD_DRAW_ARGUMENTS, nullptr);
	mtl4SetPipeline(commandBuffer, gMtl4EventStorage.signalPipelines[signal], nullptr);
	mtl4Dispatch(commandBuffer, signalOp, gridDimentions, nullptr);
	mtl4Barrier(commandBuffer, (GpuStage)GPU_STAGE_COMPUTE, (GpuStage)GPU_STAGES_ALL, GPU_HAZARD_DRAW_ARGUMENTS, nullptr);

	CMN_SET_RESULT(result, GPU_SUCCESS);
}


void mtl4WaitEvent(
	GpuCommandBuffer commandBuffer,
	GpuStage before,
	GpuOp waitOp,
	void* gpuPtr,
	uint64_t value,
	uint64_t mask,
	GpuResult* result
) {
	(void)before;

	Mtl4WaitOperation op;
	op.address = (uintptr_t)gpuPtr;
	op.value = value;
	op.mask = mask;

	void* waitOpPtr = mtl4UploadFenceWaitOp(op);

	uint32_t gridDimentions[3] = { 1, 1, 1 };
	mtl4Barrier(commandBuffer, (GpuStage)GPU_STAGES_ALL, (GpuStage)GPU_STAGE_COMPUTE, GPU_HAZARD_DRAW_ARGUMENTS, nullptr);
	mtl4SetPipeline(commandBuffer, gMtl4EventStorage.waitPipelines[waitOp], nullptr);
	mtl4Dispatch(commandBuffer, waitOpPtr, gridDimentions, nullptr);
	mtl4Barrier(commandBuffer, (GpuStage)GPU_STAGE_COMPUTE, (GpuStage)GPU_STAGES_ALL, GPU_HAZARD_DRAW_ARGUMENTS, nullptr);

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

