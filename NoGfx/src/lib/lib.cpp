#include <cassert>
#include <gpu/gpu.h>

#include <lib/layers.h>

void gpuInit(const GpuInitDesc* desc, GpuResult* result) {
	if (desc->extraLayerCount > GPU_MAX_LAYERS - 2) {
		CMN_SET_RESULT(result, GPU_TOO_MANY_LAYERS);
		return;
	}

	const GpuBaseLayer* baseLayer = gpuAcquireBaseLayerFor(desc->backend);
	if (baseLayer == nullptr) {
		CMN_SET_RESULT(result, GPU_BACKEND_NOT_SUPPORTED);
		return;
	}
	gGpuActiveLayers.baseLayer = baseLayer;

	if (desc->validationEnabled) {
		const GpuLayer* validationLayer	= gpuAcquireValidationLayerFor(desc->backend);
		if (validationLayer == nullptr) {
			CMN_SET_RESULT(result, GPU_BACKEND_NOT_SUPPORTED);
			return;
		}
		gpuPushLayer(validationLayer);
	}

	GPU_LAYERED_CALL(layerInit, desc, result);
}

void gpuDeinit(void) {
	GPU_LAYERED_CALL_NO_PARAMS_NO_RETURN(gpuDeinit);

	gGpuActiveLayers = {};
}

void gpuEnumerateDevices(GpuDeviceInfo **devices, size_t *devices_count, GpuResult *result) {
	GPU_LAYERED_CALL(gpuEnumerateDevices, devices, devices_count, result);
}

void gpuSelectDevice(GpuDeviceId deviceId, GpuResult* result) {
	GPU_LAYERED_CALL(gpuSelectDevice, deviceId, result);
}

void* gpuMalloc(size_t bytes, size_t align, GpuMemory memory, GpuResult* result) {
	GPU_LAYERED_CALL(gpuMalloc, bytes, align, memory, result);

	return nullptr;
}

void  gpuFree(void* ptr) {
	GPU_LAYERED_CALL(gpuFree, ptr);
}

void* gpuHostToDevicePointer(void* ptr, GpuResult* result) {
	GPU_LAYERED_CALL(gpuHostToDevicePointer, ptr, result);

	return nullptr;
}

GpuTextureSizeAlign gpuTextureSizeAlign(const GpuTextureDesc* desc, GpuResult* result) {
	GPU_LAYERED_CALL(gpuTextureSizeAlign, desc, result);

	return {};
}

GpuTexture gpuCreateTexture(const GpuTextureDesc* desc, void* ptrGpu, GpuResult* result) {
	GPU_LAYERED_CALL(gpuCreateTexture, desc, ptrGpu, result);

	return 0;
}

GpuTextureDescriptor gpuTextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result) {
	GPU_LAYERED_CALL(gpuTextureViewDescriptor, texture, desc, result);

	return {};
}

GpuTextureDescriptor gpuRWTextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result) {
	GPU_LAYERED_CALL(gpuRWTextureViewDescriptor, texture, desc, result);

	return {};
}

GpuPipeline gpuCreateComputePipeline(
	const uint8_t* ir, size_t irSize,
	const void* constants, size_t constantsSize,
	uint32_t groupSize[3],
	GpuResult* result
) {
	GPU_LAYERED_CALL(gpuCreateComputePipeline, ir, irSize, constants, constantsSize, groupSize, result);

	return {};
}

GpuPipeline gpuCreateRenderPipeline(
	const uint8_t* vertexIr, size_t vertexIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* vertexConstants, size_t vertexConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	const GpuRasterDesc* desc,
	GpuResult* result
) {
	GPU_LAYERED_CALL(
		gpuCreateRenderPipeline,
		vertexIr, vertexIrSize,
		fragmentIr, fragmentIrSize,
		vertexConstants, vertexConstantsSize,
		fragmentConstants, fragmentConstantsSize,
		desc,
		result
	);

	return {};
}

GpuPipeline gpuCreateMeshletPipeline(
	const uint8_t* meshletIr, size_t meshletIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* meshletConstants, size_t meshletConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	const GpuRasterDesc* desc,
	GpuResult* result
) {
	GPU_LAYERED_CALL(
		gpuCreateMeshletPipeline,
		meshletIr, meshletIrSize,
		fragmentIr, fragmentIrSize,
		meshletConstants, meshletConstantsSize,
		fragmentConstants, fragmentConstantsSize,
		desc,
		result
	)

	return {};
}

void gpuFreePipeline(GpuPipeline pipeline) {
	GPU_LAYERED_CALL(gpuFreePipeline, pipeline);
}

GpuDepthStencilState gpuCreateDepthStencilState(const GpuDepthStencilDesc* desc, GpuResult* result) {
	GPU_LAYERED_CALL(gpuCreateDepthStencilState, desc, result);

	return {};
}

GpuBlendState gpuCreateBlendState(const GpuBlendDesc* desc, GpuResult* result) {
	GPU_LAYERED_CALL(gpuCreateBlendState, desc, result);

	return {};
}

void gpuFreeDepthStencilState(GpuDepthStencilState state) {
	GPU_LAYERED_CALL(gpuFreeDepthStencilState, state);
}

void gpuFreeBlendState(GpuBlendState state) {
	GPU_LAYERED_CALL(gpuFreeBlendState, state);
}

GpuQueue gpuCreateQueue(GpuResult* result) {
	GPU_LAYERED_CALL(gpuCreateQueue, result);

	return {};
}

GpuCommandBuffer gpuStartCommandEncoding(GpuQueue queue, GpuResult* result) {
	GPU_LAYERED_CALL(gpuStartCommandEncoding, queue, result);

	return {};
}

void gpuSubmit(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result) {
	GPU_LAYERED_CALL(gpuSubmit, queue, commandBuffers, commandBufferCount, result);
}

void gpuSubmitWithSignal(
	GpuQueue queue,
	GpuCommandBuffer* commandBuffers,
	size_t commandBufferCount,
	GpuSemaphore semaphore,
	uint64_t value,
	GpuResult* result
) {
	GPU_LAYERED_CALL(gpuSubmitWithSignal, queue, commandBuffers, commandBufferCount, semaphore, value, result);
}

GpuSemaphore gpuCreateSemaphore(uint64_t value, GpuResult* result) {
	GPU_LAYERED_CALL(gpuCreateSemaphore, value, result);

	return {};
}

void gpuWaitSemaphore(GpuSemaphore sema, uint64_t value, GpuResult* result) {
	GPU_LAYERED_CALL(gpuWaitSemaphore, sema, value, result);
}

void gpuDestroySemaphore(GpuSemaphore sema) {
	GPU_LAYERED_CALL(gpuDestroySemaphore, sema);
}

void gpuMemCpy(GpuCommandBuffer cb, void* destGpu, void* srcGpu, size_t size, GpuResult* result) {
	GPU_LAYERED_CALL(gpuMemCpy, cb, destGpu, srcGpu, size, result);
}

void gpuCopyToTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result) {
	GPU_LAYERED_CALL(gpuCopyToTexture, cb, destGpu, srcGpu, texture, result);
}

void gpuCopyFromTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result) {
	GPU_LAYERED_CALL(gpuCopyFromTexture, cb, destGpu, srcGpu, texture, result);
}

void gpuBarrier(GpuCommandBuffer cb, GpuStageFlags before, GpuStageFlags after, GpuHazardFlags hazards, GpuResult* result) {
	GPU_LAYERED_CALL(gpuBarrier, cb, before, after, hazards, result);
}

void gpuSetActiveTextureHeapPtr(GpuCommandBuffer cb, void* ptrGpu, GpuResult* result) {
	GPU_LAYERED_CALL(gpuSetActiveTextureHeapPtr, cb, ptrGpu, result);
}

void gpuSignalAfter(GpuCommandBuffer cb, GpuStageFlags before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result) {
	GPU_LAYERED_CALL(gpuSignalAfter, cb, before, ptrGpu, value, signal, result);
}

void gpuWaitBefore(GpuCommandBuffer cb, GpuStageFlags after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result) {
	GPU_LAYERED_CALL(gpuWaitBefore, cb, after, ptrGpu, value, op, hazards, mask, result);
}

void gpuSetPipeline(GpuCommandBuffer cb, GpuPipeline pipeline, GpuResult* result) {
	GPU_LAYERED_CALL(gpuSetPipeline, cb, pipeline, result);
}

void gpuSetDepthStencilState(GpuCommandBuffer cb, GpuDepthStencilState state, GpuResult* result) {
	GPU_LAYERED_CALL(gpuSetDepthStencilState, cb, state, result);
}

void gpuSetBlendState(GpuCommandBuffer cb, GpuBlendState state, GpuResult* result) {
	GPU_LAYERED_CALL(gpuSetBlendState, cb, state, result);
}

void gpuDispatch(GpuCommandBuffer cb, void* dataGpu, uint32_t gridDimensions[3], GpuResult* result) {
	GPU_LAYERED_CALL(gpuDispatch, cb, dataGpu, gridDimensions, result);
}

void gpuDispatchIndirect(GpuCommandBuffer cb, void* dataGpu, void* gridDimensionsGpu, GpuResult* result) {
	GPU_LAYERED_CALL(gpuDispatchIndirect, cb, dataGpu, gridDimensionsGpu, result);
}

void gpuBeginRenderPass(GpuCommandBuffer cb, GpuRenderPassDesc desc, GpuResult* result) {
	GPU_LAYERED_CALL(gpuBeginRenderPass, cb, desc, result);
}

void gpuEndRenderPass(GpuCommandBuffer cb, GpuResult* result) {
	GPU_LAYERED_CALL(gpuEndRenderPass, cb, result);
}

void gpuDrawIndexedInstanced(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, uint32_t indexCount, uint32_t instanceCount, GpuResult* result) {
	GPU_LAYERED_CALL(gpuDrawIndexedInstanced, cb, vertexDataGpu, pixelDataGpu, indicesGpu, indexCount, instanceCount, result);
}

void gpuDrawIndexedInstancedIndirect(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, void* argsGpu, GpuResult* result) {
	GPU_LAYERED_CALL(gpuDrawIndexedInstancedIndirect, cb, vertexDataGpu, pixelDataGpu, indicesGpu, argsGpu, result);
}

void gpuDrawIndexedInstancedIndirectMulti(GpuCommandBuffer cb, void* dataVxGpu, uint32_t vxStride, void* dataPxGpu, uint32_t pxStride, void* argsGpu, void* drawCountGpu, GpuResult* result) {
	GPU_LAYERED_CALL(gpuDrawIndexedInstancedIndirectMulti, cb, dataVxGpu, vxStride, dataPxGpu, pxStride, argsGpu, drawCountGpu, result);
}

void gpuDrawMeshlets(GpuCommandBuffer cb, void* meshletDataGpu, void* pixelDataGpu, uint32_t dim[3], GpuResult* result) {
	GPU_LAYERED_CALL(gpuDrawMeshlets, cb, meshletDataGpu, pixelDataGpu, dim, result);
}

void gpuDrawMeshletsIndirect(GpuCommandBuffer cb, void* meshletDataGpu, void* pixelDataGpu, void *dimGpu, GpuResult* result) {
	GPU_LAYERED_CALL(gpuDrawMeshletsIndirect, cb, meshletDataGpu, pixelDataGpu, dimGpu, result);
}

