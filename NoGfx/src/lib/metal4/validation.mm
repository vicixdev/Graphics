#include "validation.h"

#include <lib/common/memory.h>
#include <lib/metal4/context.h>
#include <lib/metal4/allocation.h>
#include <lib/metal4/textures.h>
#include <lib/metal4/surfaces.h>

static uint32_t mtl4MaxMipCountFor(const GpuTextureDesc* desc) {
	uint32_t maxDimension = desc->dimensions[0];

	if (desc->dimensions[1] > maxDimension) {
		maxDimension = desc->dimensions[1];
	}

	if (desc->type == GPU_TEXTURE_3D && desc->dimensions[2] > maxDimension) {
		maxDimension = desc->dimensions[2];
	}

	uint32_t maxMipCount = 1;
	while (maxDimension > 1) {
		maxDimension >>= 1;
		maxMipCount++;
	}

	return maxMipCount;
}

static bool mtl4IsValidFormat(GpuFormat format) {
	return format <= GPU_FORMAT_BC5_UNORM;
}

static bool mtl4ValidateBlendDescValues(const GpuBlendDesc* desc) {
	return
		desc->colorOp <= GPU_BLEND_MAX &&
		desc->srcColorFactor <= GPU_FACTOR_SRC_ALPHA &&
		desc->dstColorFactor <= GPU_FACTOR_SRC_ALPHA &&
		desc->alphaOp <= GPU_BLEND_MAX &&
		desc->srcAlphaFactor <= GPU_FACTOR_SRC_ALPHA &&
		desc->dstAlphaFactor <= GPU_FACTOR_SRC_ALPHA &&
		(desc->colorWriteMask & ~0xF) == 0;
}

static bool mtl4ValidateDepthStencilDescValues(const GpuDepthStencilDesc* desc) {
	if (desc->depthTest > GPU_OP_ALWAYS) {
		return false;
	}

	if ((desc->depthMode & ~(GPU_DEPTH_READ | GPU_DEPTH_WRITE)) != 0) {
		return false;
	}

	return
		desc->stencilFront.test <= GPU_OP_ALWAYS &&
		desc->stencilFront.failOp <= GPU_OP_ALWAYS &&
		desc->stencilFront.passOp <= GPU_OP_ALWAYS &&
		desc->stencilFront.depthFailOp <= GPU_OP_ALWAYS &&
		desc->stencilBack.test <= GPU_OP_ALWAYS &&
		desc->stencilBack.failOp <= GPU_OP_ALWAYS &&
		desc->stencilBack.passOp <= GPU_OP_ALWAYS &&
		desc->stencilBack.depthFailOp <= GPU_OP_ALWAYS;
}

static bool mtl4ValidateRasterDescValues(const GpuRasterDesc* desc, GpuResult* result) {
	if (desc->topology > GPU_TOPOLOGY_TRIANGLE_FAN) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->cull > GPU_CULL_NONE) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->sampleCount == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (!mtl4IsValidFormat(desc->depthFormat) || !mtl4IsValidFormat(desc->stencilFormat)) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->colorTargetCount > 0 && desc->colorTargets == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	for (size_t i = 0; i < desc->colorTargetCount; i++) {
		const GpuColorTarget* colorTarget = &desc->colorTargets[i];

		if (!mtl4IsValidFormat(colorTarget->format) || (colorTarget->writeMask & ~0xF) != 0) {
			CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
			return false;
		}
	}

	if (desc->blendstate != nullptr && !mtl4ValidateBlendDescValues(desc->blendstate)) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

static bool mtl4ValidateRenderTargetTexture(GpuTexture texture, GpuResult* result) {
	if (texture == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	Mtl4Texture handle = mtl4GpuTextureToHadle(texture);
	if (mtl4IsTextureScheduledForDeletion(handle)) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	Mtl4TextureMetadata* metadata = mtl4AcquireTextureMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_TEXTURE_FOUND);
		return false;
	}
	defer (mtl4ReleaseTextureMetadata());

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

static bool mtl4ValidateRenderPassDescValues(const GpuRenderPassDesc* desc, GpuResult* result) {
	if (desc->colorTargetCount > 0 && desc->colorTargets == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->colorTargetCount == 0 && desc->depthTarget == nullptr && desc->stencilTarget == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	for (size_t i = 0; i < desc->colorTargetCount; i++) {
		const GpuRenderTarget* target = &desc->colorTargets[i];

		if (target->loadOp > GPU_OP_DONT_CARE || target->storeOp > GPU_OP_DONT_CARE) {
			CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
			return false;
		}

		if (!mtl4ValidateRenderTargetTexture(target->texture, result)) {
			return false;
		}
	}

	if (desc->depthTarget != nullptr) {
		if (desc->depthTarget->loadOp > GPU_OP_DONT_CARE || desc->depthTarget->storeOp > GPU_OP_DONT_CARE) {
			CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
			return false;
		}

		if (!mtl4ValidateRenderTargetTexture(desc->depthTarget->texture, result)) {
			return false;
		}
	}

	if (desc->stencilTarget != nullptr) {
		if (desc->stencilTarget->loadOp > GPU_OP_DONT_CARE || desc->stencilTarget->storeOp > GPU_OP_DONT_CARE) {
			CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
			return false;
		}

		if (!mtl4ValidateRenderTargetTexture(desc->stencilTarget->texture, result)) {
			return false;
		}
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateEnumerateDevices(GpuDeviceInfo** devices, size_t* devices_count, GpuResult* result) {
	if (devices == nullptr || devices_count == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateSelectDevice(GpuDeviceId deviceId, GpuResult* result) {
	if (deviceId >= gMtl4Context.availableDevices.count) {
		CMN_SET_RESULT(result, GPU_INVALID_DEVICE);
		return false;
	}

	if (gMtl4Context.device != nullptr) {
		CMN_SET_RESULT(result, GPU_DEVICE_ALREADY_SELECTED);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateMalloc(size_t bytes, size_t align, GpuMemory memory, GpuResult* result) {
	(void)align;

	if (bytes == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (memory > GPU_MEMORY_READBACK) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateFree(void *ptr) {
	(void)ptr;

	return true;
}

bool mtl4ValidateHostToDevicePointer(void* ptr, GpuResult* result) {
	if (ptr == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFrom(ptr, true);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	if (mtl4IsAllocationScheduledForDeletion(metadata)) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}
	
	if (mtl4IsGpuAddress(metadata, ptr)) {
		CMN_SET_RESULT(result, GPU_ALLOCATION_MEMORY_IS_GPU);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateTextureDesc(const GpuTextureDesc* desc, GpuResult* result) {
	if (desc == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->type > GPU_TEXTURE_CUBE_ARRAY) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->format == GPU_FORMAT_NONE || desc->format > GPU_FORMAT_BC5_UNORM) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->usage > GPU_USAGE_DEPTH_STENCIL_ATTACHMENT) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->mipCount == 0 || desc->sampleCount == 0 || desc->dimensions[0] == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	switch (desc->type) {
		case GPU_TEXTURE_1D: {
			if (desc->dimensions[1] != 1 || desc->dimensions[2] != 1 || desc->layerCount != 1) {
				CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
				return false;
			}
			break;
		}

		case GPU_TEXTURE_2D: {
			if (desc->dimensions[1] == 0 || desc->dimensions[2] != 1 || desc->layerCount != 1) {
				CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
				return false;
			}
			break;
		}

		case GPU_TEXTURE_3D: {
			if (desc->dimensions[1] == 0 || desc->dimensions[2] == 0 || desc->layerCount != 1) {
				CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
				return false;
			}
			break;
		}

		case GPU_TEXTURE_CUBE: {
			if (
				desc->dimensions[1] == 0 ||
				desc->dimensions[2] != 1 ||
				desc->layerCount != 1 ||
				desc->dimensions[0] != desc->dimensions[1]
			) {
				CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
				return false;
			}
			break;
		}

		case GPU_TEXTURE_2D_ARRAY: {
			if (desc->dimensions[1] == 0 || desc->dimensions[2] != 1 || desc->layerCount == 0) {
				CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
				return false;
			}
			break;
		}

		case GPU_TEXTURE_CUBE_ARRAY: {
			if (
				desc->dimensions[1] == 0 ||
				desc->dimensions[2] != 1 ||
				desc->layerCount == 0 ||
				desc->dimensions[0] != desc->dimensions[1]
			) {
				CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
				return false;
			}
			break;
		}
	}

	if (desc->mipCount > mtl4MaxMipCountFor(desc)) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateTextureSizeAlign(const GpuTextureDesc* desc, GpuResult* result) {
	return mtl4ValidateTextureDesc(desc, result);
}

bool mtl4ValidateCreateTexture(const GpuTextureDesc* desc, void* ptrGpu, GpuResult* result) {
	if (!mtl4ValidateTextureDesc(desc, result)) {
		return false;
	}

	if (ptrGpu == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFrom(ptrGpu, true);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	if (mtl4IsCpuAddress(metadata, ptrGpu)) {
		CMN_SET_RESULT(result, GPU_ALLOCATION_MEMORY_IS_CPU);
		return false;
	}

	if (mtl4IsAllocationScheduledForDeletion(metadata)) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}
	
	if (metadata->memory != GPU_MEMORY_GPU) {
		CMN_SET_RESULT(result, GPU_ALLOCATION_MEMORY_IS_CPU);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateTextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result) {
	if (desc == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->format == GPU_FORMAT_NONE || desc->format > GPU_FORMAT_BC5_UNORM) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->mipCount == 0 || desc->layerCount == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (mtl4IsTextureScheduledForDeletion(mtl4GpuTextureToHadle(texture))) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	Mtl4Texture handle = mtl4GpuTextureToHadle(texture);
	Mtl4TextureMetadata* metadata = mtl4AcquireTextureMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_TEXTURE_FOUND);
		return false;
	}
	defer (mtl4ReleaseTextureMetadata());

	if (desc->baseMip >= metadata->texture.mipmapLevelCount) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if ((uint32_t)desc->baseMip + (uint32_t)desc->mipCount > metadata->texture.mipmapLevelCount) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	uint32_t maxLayerCount = 1;
	switch (metadata->texture.textureType) {
		case MTLTextureType3D: {
			maxLayerCount = (uint32_t)metadata->texture.depth;
			break;
		}
		case MTLTextureType2DArray:
		case MTLTextureTypeCubeArray: {
			maxLayerCount = (uint32_t)metadata->texture.arrayLength;
			break;
		}
		default: {
			maxLayerCount = 1;
			break;
		}
	}

	if (desc->baseLayer >= maxLayerCount) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if ((uint32_t)desc->baseLayer + (uint32_t)desc->layerCount > maxLayerCount) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateRWTextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result) {
	return mtl4ValidateTextureViewDescriptor(texture, desc, result);
}

bool mtl4CheckSynchronization(Mtl4CommandBufferMetadata* metadata, GpuStageFlags before, GpuStageFlags after, GpuResult* result) {
	(void)before;
	(void)after;

	if (metadata->isEncodingRenderpass) {
		CMN_SET_RESULT(result, GPU_SYNCHRONIZATION_WHILE_ENCODING_RENDERPASS);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateCreateSurface(const GpuSurfaceDesc* desc, GpuResult* result) {
	if (desc->format != GPU_FORMAT_RGBA8_UNORM) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->framesInFlight != 2 && desc->framesInFlight != 3) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->size[0] == 0 || desc->size[1] == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->target.type != GPU_SURFACE_COCOA) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc->target.cocoa.nsView == nil) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateResizeSurface(GpuSurface surface, uint32_t size[2], GpuResult* result) {
	if (size == nullptr || size[0] == 0 || size[1] == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (mtl4IsSurfaceScheduledForDeletion(mtl4GpuSurfaceToHandle(surface))) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateFreeSurface(GpuSurface surface) {
	(void)surface;
	return true;
}

bool mtl4ValidateAcquireNextDrawable(GpuSurface surface, GpuResult* result) {
	if (mtl4IsSurfaceScheduledForDeletion(mtl4GpuSurfaceToHandle(surface))) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateCreateComputePipeline(
	const uint8_t* ir, size_t irSize,
	const void* constants, size_t constantsSize,
	uint32_t groupSize[3],
	GpuResult* result
) {
	if (ir == nullptr || irSize == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (constants == nullptr && constantsSize != 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (constantsSize % 4 != 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (groupSize == nullptr || groupSize[0] == 0 || groupSize[1] == 0 || groupSize[2] == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateCreateRenderPipeline(
	const uint8_t* vertexIr, size_t vertexIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* vertexConstants, size_t vertexConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	const GpuRasterDesc* desc,
	GpuResult* result
) {
	if (vertexIr == nullptr || vertexIrSize == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (fragmentIr == nullptr || fragmentIrSize == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}
	
	if (vertexConstants == nullptr && vertexConstantsSize != 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (fragmentConstants == nullptr && fragmentConstantsSize != 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (vertexConstantsSize % 4 != 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (fragmentConstantsSize % 4 != 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	return mtl4ValidateRasterDescValues(desc, result);
}

bool mtl4ValidateCreateMeshletPipeline(
	const uint8_t* meshletIr, size_t meshletIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* meshletConstants, size_t meshletConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	const GpuRasterDesc* desc,
	GpuResult* result
) {
	if (meshletIr == nullptr || meshletIrSize == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (fragmentIr == nullptr || fragmentIrSize == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}
	
	if (meshletConstants == nullptr && meshletConstantsSize != 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (fragmentConstants == nullptr && fragmentConstantsSize != 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (meshletConstantsSize % 4 != 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (fragmentConstantsSize % 4 != 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (desc == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	return mtl4ValidateRasterDescValues(desc, result);
}

bool mtl4ValidateFreePipeline(GpuPipeline pipeline) {
	(void)pipeline;
	return true;
}

bool mtl4ValidateCreateDepthStencilState(const GpuDepthStencilDesc* desc, GpuResult* result) {
	if (desc == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (!mtl4ValidateDepthStencilDescValues(desc)) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateCreateBlendState(const GpuBlendDesc* desc, GpuResult* result) {
	if (desc == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (!mtl4ValidateBlendDescValues(desc)) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateFreeDepthStencilState(GpuDepthStencilState state) {
	(void)state;
	return true;
}

bool mtl4ValidateFreeBlendState(GpuBlendState state) {
	(void)state;
	return true;
}

bool mtl4ValidateCreateQueue(GpuResult* result) {
	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateStartCommandEncoding(GpuQueue queue, GpuResult* result) {
	(void)queue;
	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateSubmit(GpuQueue queue, GpuCommandBuffer* commandBuffers, size_t commandBufferCount, GpuResult* result) {
	(void)queue;

	if (commandBuffers == nullptr && commandBufferCount != 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateSubmitWithSignal(
	GpuQueue queue,
	GpuCommandBuffer* commandBuffers,
	size_t commandBufferCount,
	GpuSemaphore semaphore,
	uint64_t value,
	GpuResult* result
) {
	(void)queue;
	(void)value;

	if (commandBuffers == nullptr && commandBufferCount != 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (mtl4IsSemaphoreScheduledForDeletion(mtl4GpuSemaphoreToHandle(semaphore))) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidatePresent(GpuQueue queue, GpuSurface surface, GpuResult* result) {
	(void)queue;

	if (mtl4IsSurfaceScheduledForDeletion(mtl4GpuSurfaceToHandle(surface))) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateCreateSemaphore(uint64_t value, GpuResult* result) {
	(void)value;

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateWaitSemaphore(GpuSemaphore sema, uint64_t value, GpuResult* result) {
	(void)value;

	if (mtl4IsSemaphoreScheduledForDeletion(mtl4GpuSemaphoreToHandle(sema))) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	Mtl4Semaphore handle = mtl4GpuSemaphoreToHandle(sema);
	Mtl4SemaphoreMetadata* metadata = mtl4AcquireSemaphoreMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_SEMAPHORE_FOUND);
		return false;
	}
	defer (mtl4ReleaseSemaphoreMetadata());

	if (value < [metadata->event signaledValue]) {
		CMN_SET_RESULT(result, GPU_SEMAPHORE_VALUE_ALREADY_SIGNALED);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateFreeSemaphore(GpuSemaphore sema) {
	(void)sema;
	return true;
}

bool mtl4ValidateMemCpy(GpuCommandBuffer cb, void* destGpu, void* srcGpu, size_t size, GpuResult* result) {
	(void)cb;

	if (destGpu == nullptr || srcGpu == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (size == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	Mtl4AllocationMetadata* destMetadata = mtl4AcquireAllocationMetadataFrom(destGpu, true);
	if (mtl4IsAllocationScheduledForDeletion(destMetadata)) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* srcMetadata = mtl4AcquireAllocationMetadataFrom(srcGpu, true);
	if (mtl4IsAllocationScheduledForDeletion(srcMetadata)) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	if (mtl4IsCpuAddress(destMetadata, destGpu) || mtl4IsCpuAddress(srcMetadata, srcGpu)) {
		CMN_SET_RESULT(result, GPU_ALLOCATION_MEMORY_IS_CPU);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateCopyToTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result) {
	(void)cb;

	if (destGpu == nullptr || srcGpu == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (mtl4IsTextureScheduledForDeletion(mtl4GpuTextureToHadle(texture))) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	Mtl4AllocationMetadata* destMetadata = mtl4AcquireAllocationMetadataFrom(destGpu, true);
	if (mtl4IsAllocationScheduledForDeletion(destMetadata)) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* srcMetadata = mtl4AcquireAllocationMetadataFrom(srcGpu, true);
	if (mtl4IsAllocationScheduledForDeletion(srcMetadata)) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	if (mtl4IsCpuAddress(destMetadata, destGpu) || mtl4IsCpuAddress(srcMetadata, srcGpu)) {
		CMN_SET_RESULT(result, GPU_ALLOCATION_MEMORY_IS_CPU);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateCopyFromTexture(GpuCommandBuffer cb, void* destGpu, void* srcGpu, GpuTexture texture, GpuResult* result) {
	(void)cb;

	if (destGpu == nullptr || srcGpu == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (mtl4IsTextureScheduledForDeletion(mtl4GpuTextureToHadle(texture))) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	Mtl4AllocationMetadata* destMetadata = mtl4AcquireAllocationMetadataFrom(destGpu, true);
	if (mtl4IsAllocationScheduledForDeletion(destMetadata)) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* srcMetadata = mtl4AcquireAllocationMetadataFrom(srcGpu, true);
	if (mtl4IsAllocationScheduledForDeletion(srcMetadata)) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	if (mtl4IsCpuAddress(destMetadata, destGpu) || mtl4IsCpuAddress(srcMetadata, srcGpu)) {
		CMN_SET_RESULT(result, GPU_ALLOCATION_MEMORY_IS_CPU);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateSetActiveTextureHeapPtr(GpuCommandBuffer cb, void* ptrGpu, GpuResult* result) {
	(void)cb;

	if (ptrGpu == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFrom(ptrGpu, true);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	if (mtl4IsCpuAddress(metadata, ptrGpu)) {
		CMN_SET_RESULT(result, GPU_ALLOCATION_MEMORY_IS_CPU);
		return false;
	}

	if (mtl4IsAllocationScheduledForDeletion(metadata)) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}
	
	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateSetPipeline(GpuCommandBuffer cb, GpuPipeline pipeline, GpuResult* result) {
	(void)cb;

	if (mtl4IsPipelineScheduledForDeletion(mtl4GpuPipelineToHandle(pipeline))) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateSetDepthStencilState(GpuCommandBuffer cb, GpuDepthStencilState state, GpuResult* result) {
	(void)cb;

	if (mtl4IsDepthStencilStateScheduledForDeletion(mtl4GpuDepthStencilStateToHandle(state))) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateSetBlendState(GpuCommandBuffer cb, GpuBlendState state, GpuResult* result) {
	(void)cb;

	if (mtl4IsBlendStateScheduledForDeletion(mtl4GpuBlendStateToHandle(state))) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	CMN_SET_RESULT(result, GPU_UNSUPPORTED_OPERATION);
	return false;
}

bool mtl4ValidateDispatch(GpuCommandBuffer cb, void* dataGpu, uint32_t gridDimensions[3], GpuResult* result) {
	(void)cb;

	if (dataGpu == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (gridDimensions == nullptr || gridDimensions[0] == 0 || gridDimensions[1] == 0 || gridDimensions[2] == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	Mtl4AllocationMetadata* metadata = mtl4AcquireAllocationMetadataFrom(dataGpu, true);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	if (mtl4IsCpuAddress(metadata, dataGpu)) {
		CMN_SET_RESULT(result, GPU_ALLOCATION_MEMORY_IS_CPU);
		return false;
	}

	if (mtl4IsAllocationScheduledForDeletion(metadata)) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* cmdMetadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (cmdMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return false;
	}

	if (cmnIsZero(cmdMetadata->pipeline)) {
		CMN_SET_RESULT(result, GPU_NO_PIPELINE_BOUND);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateDispatchIndirect(GpuCommandBuffer cb, void* dataGpu, void* gridDimensionsGpu, GpuResult* result) {
	(void)cb;

	if (dataGpu == nullptr || gridDimensionsGpu == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	Mtl4AllocationMetadata* dataMetadata = mtl4AcquireAllocationMetadataFrom(dataGpu, true);
	if (dataMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* gridMetadata = mtl4AcquireAllocationMetadataFrom(gridDimensionsGpu, true);
	if (gridMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	if (mtl4IsCpuAddress(dataMetadata, dataGpu) || mtl4IsCpuAddress(gridMetadata, gridDimensionsGpu)) {
		CMN_SET_RESULT(result, GPU_ALLOCATION_MEMORY_IS_CPU);
		return false;
	}

	if (mtl4IsAllocationScheduledForDeletion(dataMetadata) || mtl4IsAllocationScheduledForDeletion(gridMetadata)) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* cmdMetadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (cmdMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return false;
	}

	if (cmnIsZero(cmdMetadata->pipeline)) {
		CMN_SET_RESULT(result, GPU_NO_PIPELINE_BOUND);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateBeginRenderPass(GpuCommandBuffer cb, const GpuRenderPassDesc* desc, GpuResult* result) {
	(void)cb;

	if (desc == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	return mtl4ValidateRenderPassDescValues(desc, result);
}

bool mtl4ValidateEndRenderPass(GpuCommandBuffer cb, GpuResult* result) {
	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return false;
	}

	if (!metadata->isEncodingRenderpass) {
		CMN_SET_RESULT(result, GPU_NOT_ENCODING_RENDERPASS);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateDrawIndexedInstanced(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, uint32_t indexCount, uint32_t instanceCount, GpuResult* result) {
	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return false;
	}

	if (!metadata->isEncodingRenderpass) {
		CMN_SET_RESULT(result, GPU_NOT_ENCODING_RENDERPASS);
		return false;
	}

	if (vertexDataGpu == nullptr || pixelDataGpu == nullptr || indicesGpu == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	Mtl4AllocationMetadata* vertexMetadata = mtl4AcquireAllocationMetadataFrom(vertexDataGpu, true);
	if (vertexMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* pixelMetadata = mtl4AcquireAllocationMetadataFrom(pixelDataGpu, true);
	if (pixelMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* indicesMetadata = mtl4AcquireAllocationMetadataFrom(indicesGpu, true);
	if (indicesMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	if (mtl4IsCpuAddress(vertexMetadata, vertexDataGpu) || mtl4IsCpuAddress(pixelMetadata, pixelDataGpu) || mtl4IsCpuAddress(indicesMetadata, indicesGpu)) {
		CMN_SET_RESULT(result, GPU_ALLOCATION_MEMORY_IS_CPU);
		return false;
	}

	if (mtl4IsAllocationScheduledForDeletion(vertexMetadata) || mtl4IsAllocationScheduledForDeletion(pixelMetadata) || mtl4IsAllocationScheduledForDeletion(indicesMetadata)) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	if (indexCount == 0 || instanceCount == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (cmnIsZero(metadata->pipeline)) {
		CMN_SET_RESULT(result, GPU_NO_PIPELINE_BOUND);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateDrawIndexedInstancedIndirect(GpuCommandBuffer cb, void* vertexDataGpu, void* pixelDataGpu, void* indicesGpu, void* argsGpu, GpuResult* result) {
	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return false;
	}

	if (!metadata->isEncodingRenderpass) {
		CMN_SET_RESULT(result, GPU_NOT_ENCODING_RENDERPASS);
		return false;
	}

	if (vertexDataGpu == nullptr || pixelDataGpu == nullptr || indicesGpu == nullptr || argsGpu == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	Mtl4AllocationMetadata* vertexMetadata = mtl4AcquireAllocationMetadataFrom(vertexDataGpu, true);
	if (vertexMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* pixelMetadata = mtl4AcquireAllocationMetadataFrom(pixelDataGpu, true);
	if (pixelMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* indicesMetadata = mtl4AcquireAllocationMetadataFrom(indicesGpu, true);
	if (indicesMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* argsMetadata = mtl4AcquireAllocationMetadataFrom(argsGpu, true);
	if (argsMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	if (
		mtl4IsCpuAddress(vertexMetadata, vertexDataGpu) ||
		mtl4IsCpuAddress(pixelMetadata, pixelDataGpu) ||
		mtl4IsCpuAddress(indicesMetadata, indicesGpu) ||
		mtl4IsCpuAddress(argsMetadata, argsGpu)
	) {
		CMN_SET_RESULT(result, GPU_ALLOCATION_MEMORY_IS_CPU);
		return false;
	}

	if (
		mtl4IsAllocationScheduledForDeletion(vertexMetadata) ||
		mtl4IsAllocationScheduledForDeletion(pixelMetadata) ||
		mtl4IsAllocationScheduledForDeletion(indicesMetadata) ||
		mtl4IsAllocationScheduledForDeletion(argsMetadata)
	) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	if (cmnIsZero(metadata->pipeline)) {
		CMN_SET_RESULT(result, GPU_NO_PIPELINE_BOUND);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateDrawIndexedInstancedIndirectMulti(GpuCommandBuffer cb, void* dataVxGpu, uint32_t vxStride, void* dataPxGpu, uint32_t pxStride, void* argsGpu, void* drawCountGpu, GpuResult* result) {
	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return false;
	}

	if (!metadata->isEncodingRenderpass) {
		CMN_SET_RESULT(result, GPU_NOT_ENCODING_RENDERPASS);
		return false;
	}

	if (dataVxGpu == nullptr || dataPxGpu == nullptr || argsGpu == nullptr || drawCountGpu == nullptr) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	if (vxStride == 0 || pxStride == 0) {
		CMN_SET_RESULT(result, GPU_INVALID_PARAMETERS);
		return false;
	}

	Mtl4AllocationMetadata* vxMetadata = mtl4AcquireAllocationMetadataFrom(dataVxGpu, true);
	if (vxMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* pxMetadata = mtl4AcquireAllocationMetadataFrom(dataPxGpu, true);
	if (pxMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* argsMetadata = mtl4AcquireAllocationMetadataFrom(argsGpu, true);
	if (argsMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	Mtl4AllocationMetadata* drawCountMetadata = mtl4AcquireAllocationMetadataFrom(drawCountGpu, true);
	if (drawCountMetadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_ALLOCATION_FOUND);
		return false;
	}
	defer (mtl4ReleaseAllocationMetadata());

	if (
		mtl4IsCpuAddress(vxMetadata, dataVxGpu) ||
		mtl4IsCpuAddress(pxMetadata, dataPxGpu) ||
		mtl4IsCpuAddress(argsMetadata, argsGpu) ||
		mtl4IsCpuAddress(drawCountMetadata, drawCountGpu)
	) {
		CMN_SET_RESULT(result, GPU_ALLOCATION_MEMORY_IS_CPU);
		return false;
	}

	if (
		mtl4IsAllocationScheduledForDeletion(vxMetadata) ||
		mtl4IsAllocationScheduledForDeletion(pxMetadata) ||
		mtl4IsAllocationScheduledForDeletion(argsMetadata) ||
		mtl4IsAllocationScheduledForDeletion(drawCountMetadata)
	) {
		CMN_SET_RESULT(result, GPU_USE_AFTER_FREE);
		return false;
	}

	if (cmnIsZero(metadata->pipeline)) {
		CMN_SET_RESULT(result, GPU_NO_PIPELINE_BOUND);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateDrawMeshlets(GpuCommandBuffer cb, void* meshletDataGpu, void* pixelDataGpu, uint32_t dim[3], GpuResult* result) {
	(void)cb;
	(void)meshletDataGpu;
	(void)pixelDataGpu;
	(void)dim;

	CMN_SET_RESULT(result, GPU_UNSUPPORTED_OPERATION);
	return false;
}

bool mtl4ValidateDrawMeshletsIndirect(GpuCommandBuffer cb, void* meshletDataGpu, void* pixelDataGpu, void *dimGpu, GpuResult* result) {
	(void)cb;
	(void)meshletDataGpu;
	(void)pixelDataGpu;
	(void)dimGpu;

	CMN_SET_RESULT(result, GPU_UNSUPPORTED_OPERATION);
	return false;
}

bool mtl4ValidateBarrier(GpuCommandBuffer cb, GpuStageFlags before, GpuStageFlags after, GpuHazardFlags hazards, GpuResult* result) {
	(void)hazards;

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return false;
	}

	if (!mtl4CheckSynchronization(metadata, before, after, result)) {
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateSignalAfter(GpuCommandBuffer cb, GpuStageFlags before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result) {
	(void)cb;
	(void)before;
	(void)ptrGpu;
	(void)value;

	if (signal != GPU_SIGNAL_ATOMIC_MAX) {
		CMN_SET_RESULT(result, GPU_UNSUPPORTED_OPERATION);
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

bool mtl4ValidateWaitBefore(GpuCommandBuffer cb, GpuStageFlags after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result) {
	(void)cb;
	(void)after;
	(void)ptrGpu;
	(void)value;
	(void)hazards;

	if (op != GPU_OP_GREATER_EQUAL) {
		CMN_SET_RESULT(result, GPU_UNSUPPORTED_OPERATION);
		return false;
	}

	if (mask != GPU_DEFAULT_WAIT_MASK) {
		CMN_SET_RESULT(result, GPU_UNSUPPORTED_OPERATION);
		return false;
	}

	Mtl4CommandBuffer handle = mtl4GpuCommandBufferToHandle(cb);
	Mtl4CommandBufferMetadata* metadata = mtl4AcquireCommandBufferMetadataFrom(handle);
	if (metadata == nullptr) {
		CMN_SET_RESULT(result, GPU_NO_SUCH_COMMAND_BUFFER_FOUND);
		return false;
	}

	if (!mtl4CheckSynchronization(metadata, 0, after, result)) {
		return false;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return true;
}

