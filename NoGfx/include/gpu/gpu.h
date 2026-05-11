#ifndef GFX_GFX_H
#define GFX_GFX_H

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

typedef enum GpuResult {
	GPU_SUCCESS = 0,

	GPU_BACKEND_NOT_SUPPORTED,
	GPU_TOO_MANY_LAYERS,
	GPU_INVALID_DEVICE,
	GPU_DEVICE_ALREADY_SELECTED,
	GPU_DEVICE_NOT_SELECTED,
	GPU_OUT_OF_CPU_MEMORY,
	GPU_OUT_OF_GPU_MEMORY,

	GPU_INVALID_PARAMETERS,
	GPU_NO_SUCH_ALLOCATION_FOUND,
	GPU_NO_SUCH_TEXTURE_FOUND,
	GPU_NO_SUCH_QUEUE_FOUND,
	GPU_NO_SUCH_COMMAND_BUFFER_FOUND,
	GPU_NO_SUCH_PIPELINE_FOUND,
	GPU_NO_SUCH_SEMAPHORE_FOUND,
	GPU_ALLOCATION_MEMORY_IS_GPU,
	GPU_ALLOCATION_MEMORY_IS_CPU,

	GPU_PIPELINE_IR_VALIDATION_FAILED,
	GPU_INCOMPATIBLE_PIPELINE,

	GPU_TOO_MANY_UNSUBMITTED_COMMAND_BUFFERS,
	GPU_ALREADY_SUBMITTED,

	GPU_COUND_NOT_CREATE_QUEUE,
	GPU_COUND_NOT_CREATE_COMMAND_BUFFER,

	GPU_UNSUPPORTED_OPERATION,

	// Only active while validation is enabled.
	GPU_USE_AFTER_FREE,

	GPU_GENERAL_ERROR,
} GpuResult;

typedef enum GpuBackend {
	GPU_NONE = 0,
	GPU_METAL_4,
	GPU_VULKAN,
	// ...
} GpuBackend;

typedef enum GpuDeviceType {
	GPU_INTEGRATED = 0,
	GPU_DEDICATED,
} GpuDeviceType;

typedef enum GpuMemory {
	GPU_MEMORY_DEFAULT = 0,
	GPU_MEMORY_GPU,
	GPU_MEMORY_READBACK,
} GpuMemory;

typedef enum GpuTextureType {
	GPU_TEXTURE_1D = 0,
	GPU_TEXTURE_2D,
	GPU_TEXTURE_3D,
	GPU_TEXTURE_CUBE,
	GPU_TEXTURE_2D_ARRAY,
	GPU_TEXTURE_CUBE_ARRAY,
} GpuTextureType;

typedef enum GpuFormat {
	GPU_FORMAT_NONE = 0,
	GPU_FORMAT_R8_UNORM,
	GPU_FORMAT_RG8_UNORM,
	GPU_FORMAT_RGBA8_UNORM,
	GPU_FORMAT_RGBA8_SRGB,
	GPU_FORMAT_BGRA8_UNORM,
	GPU_FORMAT_BGRA8_SRGB,
	GPU_FORMAT_R16_FLOAT,
	GPU_FORMAT_RG16_FLOAT,
	GPU_FORMAT_RGBA16_FLOAT,
	GPU_FORMAT_RGBA16_UNORM,
	GPU_FORMAT_R16_UNORM,
	GPU_FORMAT_RG16_UNORM,
	GPU_FORMAT_R32_FLOAT,
	GPU_FORMAT_RG32_FLOAT,
	GPU_FORMAT_RGBA32_FLOAT,
	GPU_FORMAT_RG11B10_FLOAT,
	GPU_FORMAT_RGB10_A2_UNORM,
	GPU_FORMAT_RGB10_A2_UINT,
	GPU_FORMAT_D32_FLOAT,
	GPU_FORMAT_D24_UNORM_S8_UINT,
	GPU_FORMAT_D32_FLOAT_S8_UINT,
	GPU_FORMAT_D16_UNORM,
	GPU_FORMAT_BC1_RGBA_UNORM,
	GPU_FORMAT_BC1_RGBA_SRGB,
	GPU_FORMAT_BC4_UNORM,
	GPU_FORMAT_BC5_UNORM,
} GpuFormat;

typedef enum GpuUsage {
	GPU_USAGE_SAMPLED = 0,
	GPU_USAGE_STORAGE,
	GPU_USAGE_COLOR_ATTACHMENT,
	GPU_USAGE_DEPTH_STENCIL_ATTACHMENT,
} GpuUsage;

typedef enum GpuStage {
	GPU_STAGE_TRANSFER = 0x1,
	GPU_STAGE_COMPUTE = 0x2,
	GPU_STAGE_RASTER_COLOR_OUT = 0x4,
	GPU_STAGE_PIXEL_SHADER = 0x8,
	GPU_STAGE_VERTEX_SHADER = 0x10,
} GpuStage;
typedef size_t GpuStageFlags; // bitfield of GpuStage

typedef enum GpuHazard {
	GPU_HAZARD_NONE = 0,
	GPU_HAZARD_DRAW_ARGUMENTS = 0x1,
	GPU_HAZARD_DESCRIPTORS = 0x2,
	GPU_HAZARD_DEPTH_STENCIL = 0x4
} GpuHazard;
typedef size_t GpuHazardFlags; // bitfield of GpuHazard

typedef enum GpuOp {
	GPU_OP_NEVER = 0,
	GPU_OP_LESS,
	GPU_OP_EQUAL,
	GPU_OP_LESS_EQUAL,
	GPU_OP_GREATER,
	GPU_OP_NOT_EQUAL,
	GPU_OP_GREATER_EQUAL,
	GPU_OP_ALWAYS,
} GpuOp;

typedef enum GpuSignal {
	GPU_SIGNAL_ATOMIC_SET = 0,
	GPU_SIGNAL_ATOMIC_MAX,
	GPU_SIGNAL_ATOMIC_OR,
	// ...
} GpuSignal;

#define GPU_DEFAULT_WAIT_MASK (~(uint64_t)0)

typedef size_t GpuDeviceId;
typedef uint64_t GpuTexture;
typedef uint64_t GpuPipeline;
typedef uint64_t GpuQueue;
typedef uint64_t GpuCommandBuffer;
typedef uint64_t GpuSemaphore;

typedef struct GpuDeviceCapabilites {
	const GpuSignal* supportedSignals;
	size_t supportedSignalCount;

	const GpuOp* supportedWaitOps;
	size_t supportedWaitOpCount;

	bool supportsArbitraryWaitMask;
	bool gpuReadableSignals;
	bool gpuWritableSignals;

	// TODO: more capabilities...
} GpuDeviceCapabilites;

typedef struct GpuDeviceInfo {
	GpuDeviceId identifier;
	const char* name;
	const char* vendor;
	GpuDeviceType type;

	GpuDeviceCapabilites capabilities;

	// TODO: limits...
} GpuDeviceInfo;

typedef struct GpuTextureDesc { 
	GpuTextureType type;
	uint32_t dimensions[3];
	uint32_t mipCount;
	uint32_t layerCount;
	uint32_t sampleCount;
	GpuFormat format; 
	GpuUsage usage;
} GpuTextureDesc;

typedef struct GpuTextureSizeAlign {
	size_t size;
	size_t align;
} GpuTextureSizeAlign;

typedef struct GpuTextureDescriptor {
	uint64_t data[4];
} GpuTextureDescriptor;

typedef struct GpuViewDesc {
	GpuFormat format;
	uint8_t baseMip;
	uint8_t mipCount;
	uint16_t baseLayer;
	uint16_t layerCount;
} GpuViewDesc;

struct GpuInitDesc;

typedef struct GpuLayer {
	bool (*layerInit)(const struct GpuInitDesc* desc, GpuResult* result);
	bool (*gpuDeinit)(void);

	bool (*gpuEnumerateDevices)(GpuDeviceInfo** devices, size_t* devices_count, GpuResult* result);
	bool (*gpuSelectDevice)(GpuDeviceId deviceId, GpuResult* result);

	bool (*gpuMalloc)(size_t bytes, size_t align, GpuMemory memory, GpuResult* result);
	bool (*gpuFree)(void* ptr);
	bool (*gpuHostToDevicePointer)(void* ptr, GpuResult* result);

	bool (*gpuTextureSizeAlign)(const GpuTextureDesc* desc, GpuResult* result);
	bool (*gpuCreateTexture)(const GpuTextureDesc* desc, void* ptrGpu, GpuResult* result);
	bool (*gpuTextureViewDescriptor)(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result);
	bool (*gpuRWTextureViewDescriptor)(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result);

	bool (*gpuCreateComputePipeline)(
		const uint8_t* ir, size_t irSize,
		const void* constants, size_t constantsSize,
		GpuResult* result
	);
	bool (*gpuCreateRenderPipeline)(
		const uint8_t* vertexIr, size_t vertexIrSize,
		const uint8_t* fragmentIr, size_t fragmentIrSize,
		const void* vertexConstants, size_t vertexConstantsSize,
		const void* fragmentConstants, size_t fragmentConstantsSize,
		GpuResult* result
	);
	bool (*gpuCreateMeshletPipeline)(
		const uint8_t* meshletIr, size_t meshletIrSize,
		const uint8_t* fragmentIr, size_t fragmentIrSize,
		const void* meshletConstants, size_t meshletConstantsSize,
		const void* fragmentConstants, size_t fragmentConstantsSize,
		GpuResult* result
	);
	bool (*gpuFreePipeline)(GpuPipeline pipeline);

	bool (*gpuCreateQueue)(GpuResult* result);
	bool (*gpuStartCommandEncoding)(GpuQueue queue, GpuResult* result);
	bool (*gpuSubmit)(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result);
	bool (*gpuSubmitWithSignal)(
		GpuQueue queue,
		GpuCommandBuffer* commandBuffers,
		size_t commandBufferCount,
		GpuSemaphore semaphore,
		uint64_t value,
		GpuResult* result
	);

	bool (*gpuCreateSemaphore)(uint64_t value, GpuResult* result);
	bool (*gpuWaitSemaphore)(GpuSemaphore sema, uint64_t value, GpuResult* result);
	bool (*gpuDestroySemaphore)(GpuSemaphore sema);

	bool (*gpuMemCpy)(GpuCommandBuffer cb, void* destGpu, void* srcGpu, size_t size, GpuResult* result);
	bool (*gpuCopyToTexture)(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result);
	bool (*gpuCopyFromTexture)(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result);

	bool (*gpuBarrier)(GpuCommandBuffer cb, GpuStage before, GpuStage after, GpuHazardFlags hazards, GpuResult* result);
	bool (*gpuSignalAfter)(GpuCommandBuffer cb, GpuStage before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result);
	bool (*gpuWaitBefore)(GpuCommandBuffer cb, GpuStage after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result);

	bool (*gpuSetPipeline)(GpuCommandBuffer cb, GpuPipeline pipeline, GpuResult* result);
	bool (*gpuDispatch)(GpuCommandBuffer cb, void* dataGpu, uint32_t gridDimensions[3], GpuResult* result);
} GpuLayer;

typedef struct GpuInitDesc {
	GpuBackend backend;
	bool validationEnabled;
	bool tracingEnabled;
	GpuLayer* extraLayers;
	size_t extraLayerCount;
} GpuInitDesc;

void gpuInit(const GpuInitDesc* desc, GpuResult* result);
void gpuDeinit(void);

void gpuEnumerateDevices(GpuDeviceInfo** devices, size_t* devices_count, GpuResult* result);
void gpuSelectDevice(GpuDeviceId deviceId, GpuResult* result);

void* gpuMalloc(size_t bytes, size_t align, GpuMemory memory, GpuResult* result);
void  gpuFree(void* ptr);
void* gpuHostToDevicePointer(void* ptr, GpuResult* result);

GpuTextureSizeAlign gpuTextureSizeAlign(const GpuTextureDesc* desc, GpuResult* result);
GpuTexture gpuCreateTexture(const GpuTextureDesc* desc, void* ptrGpu, GpuResult* result);
GpuTextureDescriptor gpuTextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result);
GpuTextureDescriptor gpuRWTextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result);

GpuPipeline gpuCreateComputePipeline(
	const uint8_t* ir, size_t irSize,
	const void* constants, size_t constantsSize,
	GpuResult* result
);
GpuPipeline gpuCreateRenderPipeline(
	const uint8_t* vertexIr, size_t vertexIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* vertexConstants, size_t vertexConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	GpuResult* result
);
GpuPipeline gpuCreateMeshletPipeline(
	const uint8_t* meshletIr, size_t meshletIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* meshletConstants, size_t meshletConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	GpuResult* result
);
void gpuFreePipeline(GpuPipeline pipeline);

GpuQueue gpuCreateQueue(GpuResult* result);
GpuCommandBuffer gpuStartCommandEncoding(GpuQueue queue, GpuResult* result);
void gpuSubmit(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result);
void gpuSubmitWithSignal(
	GpuQueue queue,
	GpuCommandBuffer* commandBuffers,
	size_t commandBufferCount,
	GpuSemaphore semaphore,
	uint64_t value,
	GpuResult* result
);

GpuSemaphore gpuCreateSemaphore(uint64_t value, GpuResult* result);
void gpuWaitSemaphore(GpuSemaphore sema, uint64_t value, GpuResult* result);
void gpuDestroySemaphore(GpuSemaphore sema);

void gpuMemCpy(GpuCommandBuffer cb, void* destGpu, void* srcGpu, size_t size, GpuResult* result);
void gpuCopyToTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result);
void gpuCopyFromTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result);

void gpuSetActiveTextureHeapPtr(GpuCommandBuffer cb, void* ptrGpu, GpuResult* result);

void gpuBarrier(GpuCommandBuffer cb, GpuStage before, GpuStage after, GpuHazardFlags hazards, GpuResult* result);
void gpuSignalAfter(GpuCommandBuffer cb, GpuStage before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result);
void gpuWaitBefore(GpuCommandBuffer cb, GpuStage after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result);

void gpuSetPipeline(GpuCommandBuffer cb, GpuPipeline pipeline, GpuResult* result);
// void gpuSetDepthStencilState(GpuCommandBuffer cb, GpuDepthStencilState state);
// void gpuSetBlendState(GpuCommandBuffer cb, GpuBlendState state); 

void gpuDispatch(GpuCommandBuffer cb, void* dataGpu, uint32_t gridDimensions[3], GpuResult* result);
void gpuDispatchIndirect(GpuCommandBuffer cb, void* dataGpu, void* gridDimensionsGpu, GpuResult* result);

// void gpuBeginRenderPass(GpuCommandBuffer cb, GpuRenderPassDesc desc);
// void gpuEndRenderPass(GpuCommandBuffer cb);

// void gpuDrawIndexedInstanced(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, uint32_t indexCount, uint32_t instanceCount);
// void gpuDrawIndexedInstancedIndirect(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, void* argsGpu);
// void gpuDrawIndexedInstancedIndirectMulti(GpuCommandBuffer cb, void* dataVxGpu, uint32_t vxStride, void* dataPxGpu, uint32_t pxStride, void* argsGpu, void* drawCountGpu);

// void gpuDrawMeshlets(GpuCommandBuffer cb, void* meshletDataGpu, void* pixelDataGpu, uint32_t dim[3]);
// void gpuDrawMeshletsIndirect(GpuCommandBuffer cb, void* meshletDataGpu, void* pixelDataGpu, void *dimGpu);

#ifdef __cplusplus
} // extern "C"
#endif // __cplusplus

#endif // GFX_GFX_H
