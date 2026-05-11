#ifndef MTL4_TABLES_H
#define MTL4_TABLES_H

#include <Metal/Metal.h>

extern const MTLPixelFormat	gMtl4GpuToMtlFormat	[/*GpuFormat*/];
extern const MTLTextureType	gMtl4GpuToMtlTextureType[/*GpuTextureType*/];
extern const MTLTextureUsage	gMtl4GpuToMtlUsage	[/*GpuUsage*/];
extern const size_t		gMtl4GpuFormatPixelSize	[/*GpuFormat*/];
extern const MTLResourceOptions gMtl4ResourceOptionsFor	[/*GpuMemory*/];

#endif // MTL4_TABLES_H

