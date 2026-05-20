#ifndef MTL4_QUEUE_H
#define MTL4_QUEUE_H

#include <gpu/gpu.h>

#include <lib/common/page.h>
#include <lib/common/exponential_array.h>
#include <lib/common/rw_mutex.h>
#include <lib/metal4/command_emission.h>

#include <Metal/Metal.h>

typedef size_t Mtl4Queue;

typedef struct Mtl4QueueMetadata {
	id<MTL4CommandQueue>		queue;

	Mtl4CommandEmissionContext	emissionContext;
	CmnMutex			emissionMutex;
} Mtl4QueueMetadata;

typedef struct Mtl4QueueStorage {
	CmnPage		page;
	CmnArena	arena;

	// NOTE: Mtl4Queues are 1:1 matching with MTL4CommandQueues.
	CmnExponentialArray	<Mtl4QueueMetadata>	queues;
	CmnRWMutex	mutex;
} Mtl4QueueStorage;
extern Mtl4QueueStorage gMtl4QueueStorage;

void mtl4InitQueueStorage(GpuResult* result);
void mtl4FiniQueueStorage(void);

GpuQueue mtl4CreateQueue(GpuResult* result);

void mtl4Submit(Mtl4CommandEmissionContext* emitContext, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result);
void mtl4Submit(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result);
void mtl4SubmitWithSignal(
	GpuQueue queue,
	GpuCommandBuffer* commandBuffers,
	size_t commandBufferCount,
	GpuSemaphore semaphore,
	uint64_t value,
	GpuResult* result
);
void mtl4Present(GpuQueue queue, GpuSurface surface, GpuResult* result);

Mtl4QueueMetadata* mtl4QueueMetadataOf(Mtl4Queue queue);

Mtl4CommandEmissionContext* mtl4AcquireCommandEmissionContext(Mtl4Queue queue, GpuResult* result);
void mtl4ReleaseCommandEmissionContext(Mtl4Queue queue);

inline void mtl4LockQueue(Mtl4QueueMetadata* metadata) {
	cmnMutexLock(&metadata->emissionMutex);
}

inline void mtl4UnlockQueue(Mtl4QueueMetadata* metadata) {
	cmnMutexUnlock(&metadata->emissionMutex);
}

inline Mtl4Queue mtl4GpuQueueToHandle(GpuQueue queue) {
	return *(Mtl4Queue*)&queue;
}

inline GpuQueue mtl4HandleToGpuQueue(Mtl4Queue handle) {
	return *(GpuQueue*)&handle;
}

#endif // MTL4_QUEUE_H
