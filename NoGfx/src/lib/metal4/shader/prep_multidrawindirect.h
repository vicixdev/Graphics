#ifndef Gmtl4preparemultidrawindirecticbsbytecode_H
#define Gmtl4preparemultidrawindirecticbsbytecode_H

#include <Metal/Metal.h>

extern unsigned char gMtl4PrepareMultidrawIndirectIcbsBytecode[17254];

typedef struct Mtl4PrepareMultidrawIndirectIcbsArgs {
	MTLResourceID				commandBuffer;

	uintptr_t				textureHeap;
	uintptr_t				fragmentData;
	uintptr_t				vertexData;
	uintptr_t				args;
	uintptr_t				argCount;

	uintptr_t				outRange;

	size_t					icbStartOffset;
	size_t					vertexStride;
	size_t					fragmentStride;

	MTLPrimitiveType			primitive;
} Mtl4PrepareMultidrawIndirectIcbsArgs;
static_assert(sizeof(Mtl4PrepareMultidrawIndirectIcbsArgs) == 88, "Unexpected size");

#endif
