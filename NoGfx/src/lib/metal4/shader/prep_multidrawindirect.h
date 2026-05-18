#ifndef MTL4_PREPAREMULTIDRAWINDIRECT_H
#define MTL4_PREPAREMULTIDRAWINDIRECT_H

#include <Metal/Metal.h>

#include <lib/metal4/shader/prep_multidrawindirect.metal.h>

typedef struct Mtl4PrepareMultidrawIndirectIcbsArgs {
	MTLResourceID				commandBuffer;

	uintptr_t				textureHeap;
	uintptr_t				fragmentData;
	uintptr_t				vertexData;
	uintptr_t				args;
	uintptr_t				argCount;

	// GpuPtr to MTLIndirectCommandBufferExecutionRange
	uintptr_t				icbRange;
	size_t					vertexStride;
	size_t					fragmentStride;

	MTLPrimitiveType			primitive;
} Mtl4PrepareMultidrawIndirectIcbsArgs;
static_assert(sizeof(Mtl4PrepareMultidrawIndirectIcbsArgs) == 80, "Unexpected size");

#endif
