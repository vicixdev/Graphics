#include "queue.h"

#include <lib/metal4/context.h>
#include <lib/metal4/command_buffers.h>

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

Mtl4QueueMetadata* mtl4QueueMetadataOf(Mtl4Queue handle) {
	CmnScopedReadRWMutex guard(&gMtl4QueueStorage.mutex);

	if (handle >= gMtl4QueueStorage.queues.length) {
		return nullptr;
	}

	return &gMtl4QueueStorage.queues[handle];
}

Mtl4CommandEmissionContext* mtl4AcquireCommandEmissionContext(Mtl4Queue queue) {
	Mtl4QueueMetadata* queueMetadata = mtl4QueueMetadataOf(queue);
	if (queueMetadata == nullptr) {
		return nullptr;
	}

	mtl4LockQueue(queueMetadata);

	return &queueMetadata->emissionContext;
}

void mtl4ReleaseCommandEmissionContext(Mtl4Queue queue) {
	Mtl4QueueMetadata* queueMetadata = mtl4QueueMetadataOf(queue);
	if (queueMetadata == nullptr) {
		return;
	}

	mtl4UnlockQueue(queueMetadata);
}

