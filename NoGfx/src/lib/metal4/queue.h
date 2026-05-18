#ifndef MTL4_QUEUE_H
#define MTL4_QUEUE_H

#include <gpu/gpu.h>

#include <Metal/Metal.h>

typedef size_t Mtl4Queue;

#define MTL4_QUEUE_HANDLE (GpuQueue)(0x0BADCAFE0BADCAFE)

GpuQueue mtl4CreateQueue(GpuResult* result);
id<MTL4CommandQueue> mtl4Queue(void);

bool mtl4IsQueueValid(GpuQueue queue);

#endif // MTL4_QUEUE_H
