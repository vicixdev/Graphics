#ifndef GPU_LAYERS_H
#define GPU_LAYERS_H

#include <gpu/gpu.h>
#include <lib/common/common.h>

#define GPU_MAX_LAYERS 4

typedef struct GpuBaseLayer {
	void (*layerInit)(const GpuInitDesc* desc, GpuResult* result);
	void (*gpuDeinit)(void);

	void (*gpuEnumerateDevices)(GpuDeviceInfo** devices, size_t* devices_count, GpuResult* result);
	void (*gpuSelectDevice)(GpuDeviceId deviceId, GpuResult* result);

	void* (*gpuMalloc)(size_t bytes, size_t align, GpuMemory memory, GpuResult* result);
	void  (*gpuFree)(void* ptr);
	void* (*gpuHostToDevicePointer)(void* ptr, GpuResult* result);

	GpuTextureSizeAlign (*gpuTextureSizeAlign)(const GpuTextureDesc* desc, GpuResult* result);
	GpuTexture (*gpuCreateTexture)(const GpuTextureDesc* desc, void* ptrGpu, GpuResult* result);
	GpuTextureDescriptor (*gpuTextureViewDescriptor)(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result);
	GpuTextureDescriptor (*gpuRWTextureViewDescriptor)(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result);

	GpuPipeline (*gpuCreateComputePipeline)(
		const uint8_t* ir, size_t irSize,
		const void* constants, size_t constantsSize,
		GpuResult* result
	);
	GpuPipeline (*gpuCreateRenderPipeline)(
		const uint8_t* vertexIr, size_t vertexIrSize,
		const uint8_t* fragmentIr, size_t fragmentIrSize,
		const void* vertexConstants, size_t vertexConstantsSize,
		const void* fragmentConstants, size_t fragmentConstantsSize,
		GpuResult* result
	);
	GpuPipeline (*gpuCreateMeshletPipeline)(
		const uint8_t* meshletIr, size_t meshletIrSize,
		const uint8_t* fragmentIr, size_t fragmentIrSize,
		const void* meshletConstants, size_t meshletConstantsSize,
		const void* fragmentConstants, size_t fragmentConstantsSize,
		GpuResult* result
	);
	void (*gpuFreePipeline)(GpuPipeline pipeline);

	GpuQueue (*gpuCreateQueue)(GpuResult* result);
	GpuCommandBuffer (*gpuStartCommandEncoding)(GpuQueue queue, GpuResult* result);
	void (*gpuSubmit)(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result);
	void (*gpuSubmitWithSignal)(
		GpuQueue queue,
		GpuCommandBuffer* commandBuffers,
		size_t commandBufferCount,
		GpuSemaphore semaphore,
		uint64_t value,
		GpuResult* result
	);

	GpuSemaphore (*gpuCreateSemaphore)(uint64_t value, GpuResult* result);
	void (*gpuWaitSemaphore)(GpuSemaphore sema, uint64_t value, GpuResult* result);
	void (*gpuDestroySemaphore)(GpuSemaphore sema);

	void (*gpuMemCpy)(GpuCommandBuffer cb, void* destGpu, void* srcGpu, size_t size, GpuResult* result);
	void (*gpuCopyToTexture)(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result);
	void (*gpuCopyFromTexture)(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result);

	void (*gpuBarrier)(GpuCommandBuffer cb, GpuStageFlags before, GpuStageFlags after, GpuHazardFlags hazards, GpuResult* result);
	void (*gpuSignalAfter)(GpuCommandBuffer cb, GpuStageFlags before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result);
	void (*gpuWaitBefore)(GpuCommandBuffer cb, GpuStageFlags after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result);

	void (*gpuSetPipeline)(GpuCommandBuffer cb, GpuPipeline pipeline, GpuResult* result);
	void (*gpuDispatch)(GpuCommandBuffer cb, void* dataGpu, uint32_t gridDimensions[3], GpuResult* result);
} GpuBaseLayer;

typedef struct {
	const GpuLayer*		validationLayers[GPU_MAX_LAYERS];
	size_t			validationLayerCount;

	const GpuBaseLayer*	baseLayer;
} GpuActiveLayers;
extern GpuActiveLayers gGpuActiveLayers;

#define GPU_LAYERED_CALL_NO_PARAMS(_function)						\
do {											\
	bool _ok = true;								\
	for (size_t _i = gGpuActiveLayers.validationLayerCount; _i > 0; _i--) {		\
		auto function = gGpuActiveLayers.validationLayers[_i - 1]->_function;	\
		if (function != nullptr) {						\
			_ok = function();						\
			if (!_ok) {							\
				break;							\
			}								\
		}									\
	}										\
	if (_ok && gGpuActiveLayers.baseLayer != nullptr) {				\
		auto function = gGpuActiveLayers.baseLayer->_function;			\
		if (function != nullptr) {						\
			return function();						\
		}									\
	}										\
} while(false);

#define GPU_LAYERED_CALL_NO_PARAMS_NO_RETURN(_function)					\
do {											\
	bool _ok = true;								\
	for (size_t _i = gGpuActiveLayers.validationLayerCount; _i > 0; _i--) {		\
		auto function = gGpuActiveLayers.validationLayers[_i - 1]->_function;	\
		if (function != nullptr) {						\
			_ok = function();						\
			if (!_ok) {							\
				break;							\
			}								\
		}									\
	}										\
	if (_ok && gGpuActiveLayers.baseLayer != nullptr) {				\
		auto function = gGpuActiveLayers.baseLayer->_function;			\
		if (function != nullptr) {						\
			function();							\
		}									\
	}										\
} while(false);

#define GPU_LAYERED_CALL(_function, ...)						\
do {											\
	bool _ok = true;								\
	for (size_t _i = gGpuActiveLayers.validationLayerCount; _i > 0; _i--) {		\
		auto function = gGpuActiveLayers.validationLayers[_i - 1]->_function;	\
		if (function != nullptr) {						\
			_ok = function(__VA_ARGS__);					\
			if (!_ok) {							\
				break;							\
			}								\
		}									\
	}										\
	if (_ok && gGpuActiveLayers.baseLayer != nullptr) {				\
		auto function = gGpuActiveLayers.baseLayer->_function;			\
		if (function != nullptr) {						\
			return function(__VA_ARGS__);					\
		}									\
	}										\
} while(false);

bool gpuPushLayer(const GpuLayer* layer);

// NOTE: Platform specific
GpuBaseLayer* gpuAcquireBaseLayerFor(GpuBackend backend);

// NOTE: Platform specific
GpuLayer* gpuAcquireValidationLayerFor(GpuBackend backend);

#endif // GPU_LAYERS_H

