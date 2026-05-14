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
	GPU_COULD_NOT_CREATE_NATIVE_OBJECT,

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

typedef enum GpuTargetOp {
	GPU_OP_CLEAR = 0,
	GPU_OP_STORE,
	GPU_OP_DONT_CARE,
} GpuTargetOp;

typedef enum GpuSignal {
	GPU_SIGNAL_ATOMIC_SET = 0,
	GPU_SIGNAL_ATOMIC_MAX,
	GPU_SIGNAL_ATOMIC_OR,
	// ...
} GpuSignal;

typedef enum GpuTopology {
	GPU_TOPOLOGY_TRIANGLE_LIST = 0,
	GPU_TOPOLOGY_TRIANGLE_STRIP,
	GPU_TOPOLOGY_TRIANGLE_FAN,
} GpuTopology;

typedef enum GpuCull {
	GPU_CULL_CCW = 0,
	GPU_CULL_CW,
	GPU_CULL_ALL,
	GPU_CULL_NONE,
} GpuCull;

typedef enum GpuDepthFlag {
	GPU_DEPTH_READ = 0x1,
	GPU_DEPTH_WRITE = 0x2
} GpuDepthFlag;
typedef size_t GpuDepthFlags; // bitfield of GpuDepthFlag

typedef enum GpuBlend {
	GPU_BLEND_ADD = 0,
	GPU_BLEND_SUBTRACT,
	GPU_BLEND_REV_SUBTRACT,
	GPU_BLEND_MIN,
	GPU_BLEND_MAX,
} GpuBlend;

typedef enum GpuFactor {
	GPU_FACTOR_ZERO = 0,
	GPU_FACTOR_ONE,
	GPU_FACTOR_SRC_COLOR,
	GPU_FACTOR_DST_COLOR,
	GPU_FACTOR_SRC_ALPHA,
} GpuFactor;

#define GPU_DEFAULT_WAIT_MASK (~(uint64_t)0)

typedef size_t GpuDeviceId;
typedef uint64_t GpuTexture;
typedef uint64_t GpuPipeline;
typedef uint64_t GpuDepthStencilState;
typedef uint64_t GpuBlendState;
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

typedef struct GpuStencil {
	GpuOp test /* = OP_ALWAYS */;
	GpuOp failOp /* = OP_KEEP */;
	GpuOp passOp /* = OP_KEEP */;
	GpuOp depthFailOp /* = OP_KEEP */;
	uint8_t reference /* = 0 */;
} GpuStencil;

typedef struct GpuDepthStencilDesc {
	GpuDepthFlags depthMode /* = 0 */;
	GpuOp depthTest /* = OP_ALWAYS */;
	float depthBias /* = 0.0f */;
	float depthBiasSlopeFactor /* = 0.0f */;
	float depthBiasClamp /* = 0.0f */;
	uint8_t stencilReadMask /* = 0xff */;
	uint8_t stencilWriteMask /* = 0xff */;
	GpuStencil stencilFront;
	GpuStencil stencilBack;
} GpuDepthStencilDesc;

typedef struct GpuBlendDesc {
	GpuBlend colorOp /* = BLEND_ADD */;
	GpuFactor srcColorFactor /* = FACTOR_ONE */;
	GpuFactor dstColorFactor /* = FACTOR_ZERO */;
	GpuBlend alphaOp /* = BLEND_ADD */;
	GpuFactor srcAlphaFactor /* = FACTOR_ONE */;
	GpuFactor dstAlphaFactor /* = FACTOR_ZERO */;
	uint8_t colorWriteMask /* = 0xf */;
} GpuBlendDesc;

typedef struct GpuColorTarget {
	GpuFormat format /* = GPU_FORMAT_NONE */;
	uint8_t writeMask /* = 0xf */;
} GpuColorTarget;

typedef struct GpuRasterDesc {
	GpuTopology topology /* = TOPOLOGY_TRIANGLE_LIST */;
	GpuCull cull /* = CULL_NONE */;
	bool alphaToCoverage /* = false */;
	bool supportDualSourceBlending /* = false */;
	uint8_t sampleCount /* = 1 */;
	GpuFormat depthFormat /* = FORMAT_NONE */;
	GpuFormat stencilFormat /* = FORMAT_NONE */;
	GpuColorTarget* colorTargets /* = {} */;
	size_t colorTargetCount;
	GpuBlendDesc* blendstate /* = nullptr; */; // optional embedded blend state
} GpuRasterDesc;

typedef struct GpuRenderTarget {
	GpuTexture texture;
	GpuTargetOp loadOp;
	GpuTargetOp storeOp;

	union {
		float depthClearValue;
		uint32_t stencilClearValue;
		float clearColor[4];
	};
} GpuRenderTarget;

typedef struct GpuRenderPassDesc {
	GpuRenderTarget* depthTarget;
	GpuRenderTarget* stencilTarget;
	GpuRenderTarget* colorTargets;
	size_t colorTargetCount;
} GpuRenderPassDesc;


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
		uint32_t groupSize[3],
		GpuResult* result
	);
	bool (*gpuCreateRenderPipeline)(
		const uint8_t* vertexIr, size_t vertexIrSize,
		const uint8_t* fragmentIr, size_t fragmentIrSize,
		const void* vertexConstants, size_t vertexConstantsSize,
		const void* fragmentConstants, size_t fragmentConstantsSize,
		const GpuRasterDesc* desc,
		GpuResult* result
	);
	bool (*gpuCreateMeshletPipeline)(
		const uint8_t* meshletIr, size_t meshletIrSize,
		const uint8_t* fragmentIr, size_t fragmentIrSize,
		const void* meshletConstants, size_t meshletConstantsSize,
		const void* fragmentConstants, size_t fragmentConstantsSize,
		const GpuRasterDesc* desc,
		GpuResult* result
	);
	bool (*gpuFreePipeline)(GpuPipeline pipeline);

	bool (*gpuCreateDepthStencilState)(const GpuDepthStencilDesc* desc, GpuResult* result);
	bool (*gpuCreateBlendState)(const GpuBlendDesc* desc, GpuResult* result);
	bool (*gpuFreeDepthStencilState)(GpuDepthStencilState state);
	bool (*gpuFreeBlendState)(GpuBlendState state);

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

	bool (*gpuSetActiveTextureHeapPtr)(GpuCommandBuffer cb, void* ptrGpu, GpuResult* result);

	bool (*gpuBarrier)(GpuCommandBuffer cb, GpuStageFlags before, GpuStageFlags after, GpuHazardFlags hazards, GpuResult* result);
	bool (*gpuSignalAfter)(GpuCommandBuffer cb, GpuStageFlags before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result);
	bool (*gpuWaitBefore)(GpuCommandBuffer cb, GpuStageFlags after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result);

	bool (*gpuSetPipeline)(GpuCommandBuffer cb, GpuPipeline pipeline, GpuResult* result);
	bool (*gpuSetDepthStencilState)(GpuCommandBuffer cb, GpuDepthStencilState state, GpuResult* result);
	bool (*gpuSetBlendState)(GpuCommandBuffer cb, GpuBlendState state, GpuResult* result); 

	bool (*gpuDispatch)(GpuCommandBuffer cb, void* dataGpu, uint32_t gridDimensions[3], GpuResult* result);
	bool (*gpuDispatchIndirect)(GpuCommandBuffer cb, void* dataGpu, void* gridDimensionsGpu, GpuResult* result);

	bool (*gpuBeginRenderPass)(GpuCommandBuffer cb, GpuRenderPassDesc desc, GpuResult* result);
	bool (*gpuEndRenderPass)(GpuCommandBuffer cb, GpuResult* result);

	bool (*gpuDrawIndexedInstanced)(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, uint32_t indexCount, uint32_t instanceCount, GpuResult* result);
	bool (*gpuDrawIndexedInstancedIndirect)(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, void* argsGpu, GpuResult* result);
	bool (*gpuDrawIndexedInstancedIndirectMulti)(GpuCommandBuffer cb, void* dataVxGpu, uint32_t vxStride, void* dataPxGpu, uint32_t pxStride, void* argsGpu, void* drawCountGpu, GpuResult* result);

	bool (*gpuDrawMeshlets)(GpuCommandBuffer cb, void* meshletDataGpu, void* pixelDataGpu, uint32_t dim[3], GpuResult* result);
	bool (*gpuDrawMeshletsIndirect)(GpuCommandBuffer cb, void* meshletDataGpu, void* pixelDataGpu, void *dimGpu, GpuResult* result);
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
	uint32_t groupSize[3],
	GpuResult* result
);
GpuPipeline gpuCreateRenderPipeline(
	const uint8_t* vertexIr, size_t vertexIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* vertexConstants, size_t vertexConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	const GpuRasterDesc* desc,
	GpuResult* result
);
GpuPipeline gpuCreateMeshletPipeline(
	const uint8_t* meshletIr, size_t meshletIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* meshletConstants, size_t meshletConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	const GpuRasterDesc* desc,
	GpuResult* result
);
void gpuFreePipeline(GpuPipeline pipeline);

GpuDepthStencilState gpuCreateDepthStencilState(const GpuDepthStencilDesc* desc, GpuResult* result);
GpuBlendState gpuCreateBlendState(const GpuBlendDesc* desc, GpuResult* result);
void gpuFreeDepthStencilState(GpuDepthStencilState state);
void gpuFreeBlendState(GpuBlendState state);

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

void gpuBarrier(GpuCommandBuffer cb, GpuStageFlags before, GpuStageFlags after, GpuHazardFlags hazards, GpuResult* result);
void gpuSignalAfter(GpuCommandBuffer cb, GpuStageFlags before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result);
void gpuWaitBefore(GpuCommandBuffer cb, GpuStageFlags after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result);

void gpuSetPipeline(GpuCommandBuffer cb, GpuPipeline pipeline, GpuResult* result);
void gpuSetDepthStencilState(GpuCommandBuffer cb, GpuDepthStencilState state, GpuResult* result);
void gpuSetBlendState(GpuCommandBuffer cb, GpuBlendState state, GpuResult* result);

void gpuDispatch(GpuCommandBuffer cb, void* dataGpu, uint32_t gridDimensions[3], GpuResult* result);
void gpuDispatchIndirect(GpuCommandBuffer cb, void* dataGpu, void* gridDimensionsGpu, GpuResult* result);

void gpuBeginRenderPass(GpuCommandBuffer cb, GpuRenderPassDesc desc, GpuResult* result);
void gpuEndRenderPass(GpuCommandBuffer cb, GpuResult* result);

void gpuDrawIndexedInstanced(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, uint32_t indexCount, uint32_t instanceCount, GpuResult* result);
void gpuDrawIndexedInstancedIndirect(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, void* argsGpu, GpuResult* result);
void gpuDrawIndexedInstancedIndirectMulti(GpuCommandBuffer cb, void* dataVxGpu, uint32_t vxStride, void* dataPxGpu, uint32_t pxStride, void* argsGpu, void* drawCountGpu, GpuResult* result);

void gpuDrawMeshlets(GpuCommandBuffer cb, void* meshletDataGpu, void* pixelDataGpu, uint32_t dim[3], GpuResult* result);
void gpuDrawMeshletsIndirect(GpuCommandBuffer cb, void* meshletDataGpu, void* pixelDataGpu, void *dimGpu, GpuResult* result);

#ifdef __cplusplus
} // extern "C"
#endif // __cplusplus

#endif // GFX_GFX_H
