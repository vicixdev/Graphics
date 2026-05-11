#include "tables.h"
#include "gpu/gpu.h"

const MTLPixelFormat gMtl4GpuToMtlFormat[] = {
	/*GPU_FORMAT_NONE=*/			MTLPixelFormatInvalid,
	/*GPU_FORMAT_R8_UNORM=*/		MTLPixelFormatR8Unorm,
	/*GPU_FORMAT_RG8_UNORM=*/		MTLPixelFormatRG8Unorm,
	/*GPU_FORMAT_RGBA8_UNORM=*/		MTLPixelFormatRGBA8Unorm,
	/*GPU_FORMAT_RGBA8_SRGB=*/		MTLPixelFormatRGBA8Unorm_sRGB,
	/*GPU_FORMAT_BGRA8_UNORM=*/		MTLPixelFormatBGRA8Unorm,
	/*GPU_FORMAT_BGRA8_SRGB=*/		MTLPixelFormatBGRA8Unorm_sRGB,
	/*GPU_FORMAT_R16_FLOAT=*/		MTLPixelFormatR16Float,
	/*GPU_FORMAT_RG16_FLOAT=*/		MTLPixelFormatRG16Float,
	/*GPU_FORMAT_RGBA16_FLOAT=*/		MTLPixelFormatRGBA16Float,
	/*GPU_FORMAT_RGBA16_UNORM=*/		MTLPixelFormatRGBA16Unorm,
	/*GPU_FORMAT_R16_UNORM=*/		MTLPixelFormatR16Unorm,
	/*GPU_FORMAT_RG16_UNORM=*/		MTLPixelFormatRG16Unorm,
	/*GPU_FORMAT_R32_FLOAT=*/		MTLPixelFormatR32Float,
	/*GPU_FORMAT_RG32_FLOAT=*/		MTLPixelFormatRG32Float,
	/*GPU_FORMAT_RGBA32_FLOAT=*/		MTLPixelFormatRGBA32Float,
	/*GPU_FORMAT_RG11B10_FLOAT=*/		MTLPixelFormatRG11B10Float,
	/*GPU_FORMAT_RGB10_A2_UNORM=*/		MTLPixelFormatRGB10A2Unorm,
	/*GPU_FORMAT_RGB10_A2_UINT=*/		MTLPixelFormatRGB10A2Uint,
	/*GPU_FORMAT_D32_FLOAT=*/		MTLPixelFormatDepth32Float,
	/*GPU_FORMAT_D24_UNORM_S8_UINT=*/	MTLPixelFormatDepth24Unorm_Stencil8,
	/*GPU_FORMAT_D32_FLOAT_S8_UINT=*/	MTLPixelFormatDepth32Float_Stencil8,
	/*GPU_FORMAT_D16_UNORM=*/		MTLPixelFormatDepth16Unorm,
	/*GPU_FORMAT_BC1_RGBA_UNORM=*/		MTLPixelFormatBC1_RGBA,
	/*GPU_FORMAT_BC1_RGBA_SRGB=*/		MTLPixelFormatBC1_RGBA_sRGB,
	/*GPU_FORMAT_BC4_UNORM=*/		MTLPixelFormatBC4_RUnorm,
	/*GPU_FORMAT_BC5_UNORM=*/		MTLPixelFormatBC5_RGUnorm,
};

const MTLTextureType gMtl4GpuToMtlTextureType[] = {
	/*GPU_TEXTURE_1D=*/			MTLTextureType1D,
	/*GPU_TEXTURE_2D=*/			MTLTextureType2D,
	/*GPU_TEXTURE_3D=*/			MTLTextureType3D,
	/*GPU_TEXTURE_CUBE=*/			MTLTextureTypeCube,
	/*GPU_TEXTURE_2D_ARRAY=*/		MTLTextureType2DArray,
	/*GPU_TEXTURE_CUBE_ARRAY=*/		MTLTextureTypeCubeArray,
};

const MTLTextureUsage gMtl4GpuToMtlUsage[] = {
	/*GPU_USAGE_SAMPLED*/	 		MTLTextureUsageShaderRead,
	/*GPU_USAGE_STORAGE*/			MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite,
	/*GPU_USAGE_COLOR_ATTACHMENT*/		MTLTextureUsageRenderTarget,
	/*GPU_USAGE_DEPTH_STENCIL_ATTACHMENT*/	MTLTextureUsageRenderTarget,
};

const size_t gMtl4GpuFormatPixelSize[] = {
	/*GPU_FORMAT_NONE=*/			0,
	/*GPU_FORMAT_R8_UNORM=*/		1,
	/*GPU_FORMAT_RG8_UNORM=*/		2,
	/*GPU_FORMAT_RGBA8_UNORM=*/		4,
	/*GPU_FORMAT_RGBA8_SRGB=*/		4,
	/*GPU_FORMAT_BGRA8_UNORM=*/		4,
	/*GPU_FORMAT_BGRA8_SRGB=*/		4,
	/*GPU_FORMAT_R16_FLOAT=*/		2,
	/*GPU_FORMAT_RG16_FLOAT=*/		4,
	/*GPU_FORMAT_RGBA16_FLOAT=*/		8,
	/*GPU_FORMAT_RGBA16_UNORM=*/		8,
	/*GPU_FORMAT_R16_UNORM=*/		2,
	/*GPU_FORMAT_RG16_UNORM=*/		4,
	/*GPU_FORMAT_R32_FLOAT=*/		4,
	/*GPU_FORMAT_RG32_FLOAT=*/		8,
	/*GPU_FORMAT_RGBA32_FLOAT=*/		16,
	/*GPU_FORMAT_RG11B10_FLOAT=*/		4,
	/*GPU_FORMAT_RGB10_A2_UNORM=*/		4,
	/*GPU_FORMAT_RGB10_A2_UINT=*/		4,
	/*GPU_FORMAT_D32_FLOAT=*/		4,
	/*GPU_FORMAT_D24_UNORM_S8_UINT=*/	4,
	/*GPU_FORMAT_D32_FLOAT_S8_UINT=*/	8,
	/*GPU_FORMAT_D16_UNORM=*/		2,
	/*GPU_FORMAT_BC1_RGBA_UNORM=*/		8,	// Block size for 4x4 pixels
	/*GPU_FORMAT_BC1_RGBA_SRGB=*/		8,	// Block size for 4x4 pixels
	/*GPU_FORMAT_BC4_UNORM=*/		8,	// Block size for 4x4 pixels
	/*GPU_FORMAT_BC5_UNORM=*/		16,	// Block size for 4x4 pixels
};

const MTLResourceOptions gMtl4ResourceOptionsFor[] = {
	/*GPU_MEMORY_DEFAULT=*/		MTLResourceStorageModeShared |  MTLResourceCPUCacheModeWriteCombined,
	/*GPU_MEMORY_GPU=*/		MTLResourceStorageModePrivate,
	/*GPU_MEMORY_READBACK=*/	MTLResourceStorageModeShared | MTLResourceCPUCacheModeDefaultCache,
};

