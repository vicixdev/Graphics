#ifndef GPU_METAL4VALIDATION_H
#define GPU_METAL4VALIDATION_H

#include <gpu/gpu.h>
#include <lib/metal4/command_buffers.h>

bool mtl4ValidateEnumerateDevices(GpuDeviceInfo** devices, size_t* devices_count, GpuResult* result);
bool mtl4ValidateSelectDevice(GpuDeviceId deviceId, GpuResult* result);

bool mtl4ValidateMalloc(size_t bytes, size_t align, GpuMemory memory, GpuResult* result);
bool mtl4ValidateFree(void* ptr);
bool mtl4ValidateHostToDevicePointer(void* ptr, GpuResult* result);

bool mtl4ValidateTextureSizeAlign(const GpuTextureDesc* desc, GpuResult* result);
bool mtl4ValidateCreateTexture(const GpuTextureDesc* desc, void* ptrGpu, GpuResult* result);
bool mtl4ValidateTextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result);
bool mtl4ValidateRWTextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result);

bool mtl4ValidateCreateSurface(const GpuSurfaceDesc* desc, GpuResult* result);
bool mtl4ValidateResizeSurface(GpuSurface surface, uint32_t size[2], GpuResult* result);
bool mtl4ValidateFreeSurface(GpuSurface surface);
bool mtl4ValidateAcquireNextDrawable(GpuSurface surface, GpuResult* result);

bool mtl4ValidateCreateComputePipeline(
	const uint8_t* ir, size_t irSize,
	const void* constants, size_t constantsSize,
	uint32_t groupSize[3],
	GpuResult* result
);
bool mtl4ValidateCreateRenderPipeline(
	const uint8_t* vertexIr, size_t vertexIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* vertexConstants, size_t vertexConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	const GpuRasterDesc* desc,
	GpuResult* result
);
bool mtl4ValidateCreateMeshletPipeline(
	const uint8_t* meshletIr, size_t meshletIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* meshletConstants, size_t meshletConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	const GpuRasterDesc* desc,
	GpuResult* result
);
bool mtl4ValidateFreePipeline(GpuPipeline pipeline);

bool mtl4ValidateCreateDepthStencilState(const GpuDepthStencilDesc* desc, GpuResult* result);
bool mtl4ValidateCreateBlendState(const GpuBlendDesc* desc, GpuResult* result);
bool mtl4ValidateFreeDepthStencilState(GpuDepthStencilState state);
bool mtl4ValidateFreeBlendState(GpuBlendState state);

bool mtl4ValidateCreateQueue(GpuResult* result);
bool mtl4ValidateStartCommandEncoding(GpuQueue queue, GpuResult* result);
bool mtl4ValidateSubmit(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result);
bool mtl4ValidateSubmitWithSignal(
	GpuQueue queue,
	GpuCommandBuffer* commandBuffers,
	size_t commandBufferCount,
	GpuSemaphore semaphore,
	uint64_t value,
	GpuResult* result
);
bool mtl4ValidatePresent(GpuQueue queue, GpuSurface surface, GpuResult* result);

bool mtl4ValidateCreateSemaphore(uint64_t value, GpuResult* result);
bool mtl4ValidateWaitSemaphore(GpuSemaphore sema, uint64_t value, GpuResult* result);
bool mtl4ValidateFreeSemaphore(GpuSemaphore sema);

bool mtl4ValidateMemCpy(GpuCommandBuffer cb, void* destGpu, void* srcGpu, size_t size, GpuResult* result);
bool mtl4ValidateCopyToTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result);
bool mtl4ValidateCopyFromTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result);

bool mtl4ValidateSetActiveTextureHeapPtr(GpuCommandBuffer cb, void* ptrGpu, GpuResult* result);

bool mtl4ValidateBarrier(GpuCommandBuffer cb, GpuStageFlags before, GpuStageFlags after, GpuHazardFlags hazards, GpuResult* result);
bool mtl4ValidateSignalAfter(GpuCommandBuffer cb, GpuStageFlags before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result);
bool mtl4ValidateWaitBefore(GpuCommandBuffer cb, GpuStageFlags after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result);

bool mtl4ValidateSetPipeline(GpuCommandBuffer cb, GpuPipeline pipeline, GpuResult* result);
bool mtl4ValidateSetDepthStencilState(GpuCommandBuffer cb, GpuDepthStencilState state, GpuResult* result);
bool mtl4ValidateSetBlendState(GpuCommandBuffer cb, GpuBlendState state, GpuResult* result);

bool mtl4ValidateDispatch(GpuCommandBuffer cb, void* dataGpu, uint32_t gridDimensions[3], GpuResult* result);
bool mtl4ValidateDispatchIndirect(GpuCommandBuffer cb, void* dataGpu, void* gridDimensionsGpu, GpuResult* result);

bool mtl4ValidateBeginRenderPass(GpuCommandBuffer cb, const GpuRenderPassDesc* desc, GpuResult* result);
bool mtl4ValidateEndRenderPass(GpuCommandBuffer cb, GpuResult* result);

bool mtl4ValidateDrawIndexedInstanced(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, uint32_t indexCount, uint32_t instanceCount, GpuResult* result);
bool mtl4ValidateDrawIndexedInstancedIndirect(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, void* argsGpu, GpuResult* result);
bool mtl4ValidateDrawIndexedInstancedIndirectMulti(GpuCommandBuffer cb, void* dataVxGpu, uint32_t vxStride, void* dataPxGpu, uint32_t pxStride, void* argsGpu, void* drawCountGpu, GpuResult* result);

bool mtl4ValidateDrawMeshlets(GpuCommandBuffer cb, void* meshletDataGpu, void* pixelDataGpu, uint32_t dim[3], GpuResult* result);
bool mtl4ValidateDrawMeshletsIndirect(GpuCommandBuffer cb, void* meshletDataGpu, void* pixelDataGpu, void *dimGpu, GpuResult* result);


bool mtl4CheckSynchronization(Mtl4CommandBufferMetadata* metadata, GpuStageFlags before, GpuStageFlags after, GpuResult* result);
bool mtl4ValidateTextureDesc(const GpuTextureDesc* desc, GpuResult* result);

#endif // GPU_METAL4_VALIDATION_H

