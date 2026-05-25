#ifndef MTL4_TABLES_H
#define MTL4_TABLES_H

#include <Metal/Metal.h>

extern const MTLPixelFormat	gMtl4GpuToMtlFormat		[/*GpuFormat		*/];
extern const MTLTextureType	gMtl4GpuToMtlTextureType	[/*GpuTextureType	*/];
extern const MTLTextureUsage	gMtl4GpuToMtlUsage		[/*GpuUsage		*/];
extern const size_t		gMtl4GpuFormatPixelSize		[/*GpuFormat		*/];
extern const MTLResourceOptions gMtl4ResourceOptionsFor		[/*GpuMemory		*/];
extern const MTLCompareFunction gMtl4GpuOpToMtlCompareFunction	[/*GpuOp		*/];
extern const MTLStencilOperation gMtl4GpuOpToMtlStencilOperation[/*GpuOp		*/];
extern const MTLLoadAction	gMtl4GpuTargetOpToMtlLoadAction	[/*GpuTargetOp		*/];
extern const MTLStoreAction	gMtl4GpuTargetOpToMtlStoreAction[/*GpuTargetOp		*/];
extern const MTLPrimitiveType	gMtl4GpuTopologyToMtlPrimitive	[/*GpuTopology		*/];
extern const MTLBlendOperation	gMtl4GpuBlendToMtlBlendOperation[/*GpuBlend		*/];
extern const MTLBlendFactor	gMtl4GpuFactorToMtlBlendFactor	[/*GpuFactor		*/];

#endif // MTL4_TABLES_H

