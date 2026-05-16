#ifndef GPU_METAL4VALIDATION_H
#define GPU_METAL4VALIDATION_H

#include <gpu/gpu.h>
#include <lib/metal4/command_buffers.h>

bool mtl4ValidateEnumerateDevices(GpuDeviceInfo** devices, size_t* devices_count, GpuResult* result);
bool mtl4ValidateSelectDevice(GpuDeviceId deviceId, GpuResult* result);

bool mtl4ValidateGpuMalloc(size_t bytes, size_t align, GpuMemory memory, GpuResult* result);
bool mtl4ValidateGpuHostToDevicePointer(void* ptr, GpuResult* result);

bool mtl4ValidateTextureDesc(const GpuTextureDesc* desc, GpuResult* result);

bool mtl4ValidateGpuTextureSizeAndAlign(const GpuTextureDesc* desc, GpuResult* result);
bool mtl4ValidateGpuCreateTexture(const GpuTextureDesc* desc, void* ptrGpu, GpuResult* result);
bool mtl4ValidateGpuTextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result);
bool mtl4ValidateGpuTextureRWViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result);

bool mtl4ValidateBarrier(GpuCommandBuffer cb, GpuStageFlags before, GpuStageFlags after, GpuHazardFlags hazards, GpuResult* result);
bool mtl4ValidateGpuSignalAfter(GpuCommandBuffer cb, GpuStageFlags before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result);
bool mtl4ValidateGpuWaitBefore(GpuCommandBuffer cb, GpuStageFlags after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result);

bool mtl4CheckSynchronization(Mtl4CommandBufferMetadata* metadata, GpuStageFlags before, GpuStageFlags after, GpuResult* result);

#endif // GPU_METAL4_VALIDATION_H

