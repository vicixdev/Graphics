#ifndef TST_GPU_COMMON_H
#define TST_GPU_COMMON_H

#include "test.h"
#include <gpu/gpu.h>
#include <lib/common/atomic.h>
#include <pthread.h>

typedef struct GpuStressGate {
	uint32_t ready;
	uint32_t start;
} GpuStressGate;

inline void waitForGateReady(GpuStressGate* gate, size_t threadCount) {
	for (;;) {
		if (cmnAtomicLoad(&gate->ready, CMN_ACQUIRE) == threadCount) {
			break;
		}
		sched_yield();
	}
}

inline void gpuWaitForStressStart(GpuStressGate* gate) {
	cmnAtomicAdd(&gate->ready, 1u, CMN_RELEASE);
	while (cmnAtomicLoad(&gate->start, CMN_ACQUIRE) == 0u) {
		sched_yield();
	}
}


GpuBackend selectBackendForCurrentPlatform(void);
GpuBackend selectUnavailableBackendForCurrentPlatform(void);
GpuTextureDesc makeDefaultTextureDesc(void);
bool initGpuAndSelectFirstDevice(GpuResult* result);

bool loadBinaryFile(const char* path, uint8_t** data, size_t* size);
void freeBinaryFile(uint8_t* data);

#endif // TST_GPU_COMMON_H
