#include "validation.h"

#include <lib/common/memory.h>
#include <lib/metal4/context.h>
#include <lib/metal4/allocation.h>
#include <lib/metal4/textures.h>

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

bool mtl4ValidateGpuMalloc(size_t bytes, size_t align, GpuMemory memory, GpuResult* result) {
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

bool mtl4ValidateGpuHostToDevicePointer(void* ptr, GpuResult* result) {
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

bool mtl4ValidateGpuTextureSizeAndAlign(const GpuTextureDesc* desc, GpuResult* result) {
	return mtl4ValidateTextureDesc(desc, result);
}

bool mtl4ValidateGpuCreateTexture(const GpuTextureDesc* desc, void* ptrGpu, GpuResult* result) {
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

bool mtl4ValidateGpuTextureViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result) {
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

bool mtl4ValidateGpuTextureRWViewDescriptor(GpuTexture texture, const GpuViewDesc* desc, GpuResult* result) {
	return mtl4ValidateGpuTextureViewDescriptor(texture, desc, result);
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

bool mtl4ValidateGpuSignalAfter(GpuCommandBuffer cb, GpuStageFlags before, void* ptrGpu, uint64_t value, GpuSignal signal, GpuResult* result) {
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

bool mtl4ValidateGpuWaitBefore(GpuCommandBuffer cb, GpuStageFlags after, void* ptrGpu, uint64_t value, GpuOp op, GpuHazardFlags hazards, uint64_t mask, GpuResult* result) {
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

