#ifndef MTL4_SEMAPHORES_H
#define MTL4_SEMAPHORES_H

#include <gpu/gpu.h>
#include <Metal/Metal.h>
#include <lib/common/page.h>
#include <lib/common/storage_sync.h>
#include <lib/metal4/command_buffers.h>

typedef CmnHandle Mtl4Semaphore;

typedef struct Mtl4SemaphoreMetadata {
	id<MTLSharedEvent>	events	[MTL4_MAX_PARALLEL_COMMANDBUFFER_ENCODINGS];
	size_t	lastSignalCount;
	CmnMutex mutex;
} Mtl4SemaphoreMetadata;

typedef struct Mtl4SemaphoreStorage {
	CmnPage		page;
	CmnArena	arena;

	CmnHandleMap<Mtl4SemaphoreMetadata>	semaphores;

	CmnStorageSync	sync;
} Mtl4SemaphoreStorage;
extern Mtl4SemaphoreStorage gMtl4SemaphoreStorage;

void mtl4InitSemaphoreStorage(GpuResult* result);
void mtl4FiniSemaphoreStorage(void);

GpuSemaphore mtl4CreateSemaphore(uint64_t value, GpuResult* result);
void mtl4WaitSemaphore(GpuSemaphore sema, uint64_t value, GpuResult* result);
void mtl4DestroySemaphore(GpuSemaphore sema);

inline GpuSemaphore mtl4HandleToGpuSemaphore(Mtl4Semaphore handle) {
	return *(GpuSemaphore*)&handle;
}
inline Mtl4Semaphore mtl4GpuSemaphoreToHandle(GpuSemaphore semaphore) {
	return *(Mtl4Semaphore*)&semaphore;
}

Mtl4SemaphoreMetadata* mtl4AcquireSemaphoreMetadataFrom(Mtl4Semaphore semaphore);
void mtl4ReleaseSemaphoreMetadata(void);

#endif

