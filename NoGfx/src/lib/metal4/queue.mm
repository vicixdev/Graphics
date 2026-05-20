#include "queue.h"
#include "lib/common/result.h"

#include <lib/common/scoped_nsautoreleasepool.h>
#include <lib/metal4/context.h>
#include <lib/metal4/command_buffers.h>
#include <lib/metal4/surfaces.h>

Mtl4QueueStorage gMtl4QueueStorage;

void mtl4InitQueueStorage(GpuResult* result) {
	CmnResult localResult;

	gMtl4QueueStorage.page = cmnCreatePage(32 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	gMtl4QueueStorage.arena = cmnPageToArena(gMtl4QueueStorage.page);
	CmnAllocator allocator = cmnArenaAllocator(&gMtl4QueueStorage.arena);

	cmnCreateExponentialArray(&gMtl4QueueStorage.queues, allocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4FiniQueueStorage(void) {
	// TODO: Free all queues
	CmnExponentialArrayIterator<Mtl4QueueMetadata> iter;
	cmnCreateExponentialArrayIterator(&gMtl4QueueStorage.queues, &iter);

	Mtl4QueueMetadata* queue;
	while(cmnIterate(&iter, &queue)) {
		[queue->queue release];
	}

	cmnDestroyPage(gMtl4QueueStorage.page);

	gMtl4QueueStorage = {};
}

GpuQueue mtl4CreateQueue(GpuResult* result) {
	CmnResult localResult;
	GpuResult localGpuResult;

	Mtl4QueueMetadata metadata = {};

	metadata.queue = [gMtl4Context.device newMTL4CommandQueue];
	if (metadata.queue == nil) {
		CMN_SET_RESULT(result, GPU_COUND_NOT_CREATE_QUEUE);
		return {};
	}

	CmnScopedWriteRWMutex guard(&gMtl4QueueStorage.mutex);

	mtl4InitCommandEmissionContext(&metadata.emissionContext, &metadata, &localGpuResult);
	if (localGpuResult != GPU_SUCCESS) {
		[metadata.queue release];

		CMN_SET_RESULT(result, localGpuResult);
		return {};
	}

	Mtl4Queue handle = gMtl4QueueStorage.queues.length;
	cmnAppend(&gMtl4QueueStorage.queues, metadata, &localResult);
	if (localResult != CMN_SUCCESS) {
		[metadata.queue release];
		mtl4FiniCommandEmissionContext(&metadata.emissionContext);

		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return {};
	}

	[metadata.queue addResidencySet:gMtl4Context.residencySet];

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return mtl4HandleToGpuQueue(handle);
}

void mtl4Submit(Mtl4CommandEmissionContext* emitContext, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result) {
	bool didFindAllCommandBuffers = true;
	GpuResult lastCommandBufferError = GPU_SUCCESS;

	GpuResult localResult;
	for (size_t i = 0; i < commandBufferCount; i++) {
		Mtl4CommandBuffer commandBufferHandle = mtl4GpuCommandBufferToHandle(commandBuffers[i]);
		Mtl4CommandBufferMetadata* commandBuffer = mtl4AcquireCommandBufferMetadataFrom(commandBufferHandle);
		if (commandBuffer == nullptr) {
			didFindAllCommandBuffers = false;
			return;
		}

		for (size_t j = 0; j < commandBuffer->commands.length; j++) {
			mtl4EmitCommand(emitContext, &commandBuffer->commands[j], &localResult);
			if (localResult != GPU_SUCCESS) {
				lastCommandBufferError = localResult;
			}
		}

		CmnScopedWriteRWMutex guard(&gMtl4CommandBufferStorage.commandBuffersMutex);
		cmnRemove(&gMtl4CommandBufferStorage.commandBuffers, commandBufferHandle);
	}

	mtl4FlushCommandBuffer(emitContext);

	if (lastCommandBufferError == GPU_SUCCESS && !didFindAllCommandBuffers) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
	} else if (lastCommandBufferError != GPU_SUCCESS) {
		CMN_SET_RESULT(result, lastCommandBufferError);
	} else {
		CMN_SET_RESULT(result, GPU_SUCCESS);
	}
}

void mtl4Submit(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result) {
	GpuResult localResult;

	CmnScopedNSAutoreleasePool pool;

	Mtl4CommandEmissionContext* emitContext = mtl4AcquireCommandEmissionContext(queue, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}
	defer (mtl4ReleaseCommandEmissionContext(queue));

	mtl4Submit(emitContext, commandBuffers, commandBufferCount, result);
}

void mtl4SubmitWithSignal(
	GpuQueue queue,
	GpuCommandBuffer* commandBuffers,
	size_t commandBufferCount,
	GpuSemaphore semaphore,
	uint64_t value,
	GpuResult* result
) {
	GpuResult localResult;
	CmnScopedNSAutoreleasePool pool;

	Mtl4CommandEmissionContext* emitContext = mtl4AcquireCommandEmissionContext(queue, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}
	defer (mtl4ReleaseCommandEmissionContext(queue));

	mtl4Submit(emitContext, commandBuffers, commandBufferCount, result);
	mtl4EmitSemaphoreSignal(emitContext, mtl4GpuSemaphoreToHandle(semaphore), value, result);
}

void mtl4Present(GpuQueue queue, GpuSurface surface, GpuResult* result) {
	(void)surface;

	CmnScopedNSAutoreleasePool pool;

	GpuResult localResult;

	Mtl4Queue queueHandle = mtl4GpuQueueToHandle(queue);
	Mtl4CommandEmissionContext* commandEmissionContext = mtl4AcquireCommandEmissionContext(queueHandle, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}
	defer (mtl4ReleaseCommandEmissionContext(queueHandle));

	Mtl4Surface surfaceHandle = mtl4GpuSurfaceToHandle(surface);
	Mtl4SurfaceMetadata* surfaceMetadata = mtl4AcquireSurfaceMetadata(surfaceHandle);
	if (surfaceMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_SURFACE_FOUND);
		return;
	}
	defer (mtl4ReleaseSurfaceMetadata());

	mtl4FlushCommandBuffer(commandEmissionContext);
	[commandEmissionContext->queue signalDrawable:surfaceMetadata->currentDrawable];
	[commandEmissionContext->queue removeResidencySet:surfaceMetadata->metalLayer.residencySet];

	[surfaceMetadata->currentDrawable present];
	mtl4ReleaseDrawable(surfaceMetadata);
}

Mtl4QueueMetadata* mtl4QueueMetadataOf(Mtl4Queue handle) {
	CmnScopedReadRWMutex guard(&gMtl4QueueStorage.mutex);

	if (handle >= gMtl4QueueStorage.queues.length) {
		return nullptr;
	}

	return &gMtl4QueueStorage.queues[handle];
}

Mtl4CommandEmissionContext* mtl4AcquireCommandEmissionContext(Mtl4Queue queue, GpuResult* result) {
	Mtl4QueueMetadata* queueMetadata = mtl4QueueMetadataOf(queue);
	if (queueMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_QUEUE_FOUND);
		return nullptr;
	}

	mtl4LockQueue(queueMetadata);

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return &queueMetadata->emissionContext;
}

void mtl4ReleaseCommandEmissionContext(Mtl4Queue queue) {
	Mtl4QueueMetadata* queueMetadata = mtl4QueueMetadataOf(queue);
	if (queueMetadata == nullptr) {
		return;
	}

	mtl4UnlockQueue(queueMetadata);
}

