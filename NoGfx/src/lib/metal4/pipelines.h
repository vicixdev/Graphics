#ifndef MTL4_PIPELINE_H
#define MTL4_PIPELINE_H

#include <strings.h>

#include <gpu/gpu.h>
#include <Metal/Metal.h>

#include <lib/common/page.h>
#include <lib/common/handle_map.h>
#include <lib/common/hash_map.h>
#include <lib/common/storage_sync.h>

typedef CmnHandle Mtl4Pipeline;

typedef enum Mtl4PipelineType {
	MTL4_PIPELINE_COMPUTE,
	MTL4_PIPELINE_GRAPHICS,
	MTL4_PIPELINE_MESHLET,
} Mtl4PipelineType;

typedef struct Mtl4Ir {
	const uint8_t*	bytes;
	size_t		size;
} Mtl4Ir;

typedef struct Mtl4CompiledIr {
	// Final
	id<MTLLibrary>	library;
} Mtl4CompiledIr;

typedef struct Mtl4Function {
	MTL4FunctionDescriptor*	descriptor;
} Mtl4Function;

typedef struct Mtl4GraphicsPipelineMetadata {
	// Final
	Mtl4Function vertex;
	// Final
	Mtl4Function fragment;
} Mtl4GraphicsPipelineMetadata;

typedef struct Mtl4ComputePipelineMetadata {
	// Final
	id<MTLComputePipelineState> pso;
} Mtl4ComputePipelineMetadata;

typedef struct Mtl4MeshletPipelineMetadata {
	// Final
	Mtl4Function meshlet;
	// Final
	Mtl4Function fragment;
} Mtl4MeshletPipelineMetadata;

typedef struct Mtl4PipelineMetadata {
	// Final
	Mtl4PipelineType	type;
	// Atomic, settable once
	bool	scheduledForDeletion;

	union {
		// Final
		Mtl4ComputePipelineMetadata	compute;
		// Final
		Mtl4GraphicsPipelineMetadata	graphics;
		// Final
		Mtl4MeshletPipelineMetadata	meshlet;
	};
} Mtl4PipelineMetadata;

typedef struct Mtl4PipelineStorage {
	CmnPage		page;
	CmnArena	arena;

	id<MTL4Compiler>	compiler;

	// Let's not compile already seen functions.
	CmnHashMap	<Mtl4Ir, Mtl4CompiledIr>	compiledIrs;

	CmnHandleMap	<Mtl4PipelineMetadata>		pipelines;

	CmnStorageSync	sync;
} Mtl4PipelineStorage;
extern Mtl4PipelineStorage gMtl4PipelineStorage;

void mtl4InitPipelineStorage(GpuResult* result);
void mtl4FiniPipelineStorage(void);

GpuPipeline mtl4CreateComputePipeline(
	const uint8_t* ir, size_t irSize,
	const void* constants, size_t constantsSize,
	GpuResult* result
);
GpuPipeline mtl4CreateRenderPipeline(
	const uint8_t* vertexIr, size_t vertexIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* vertexConstants, size_t vertexConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	GpuResult* result
);
GpuPipeline mtl4CreateMeshletPipeline(
	const uint8_t* meshletIr, size_t meshletIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* meshletConstants, size_t meshletConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	GpuResult* result
);
void mtl4FreePipeline(GpuPipeline pipeline);

Mtl4CompiledIr mtl4CompileIr(const uint8_t* ir, size_t irSize, GpuResult* result);
Mtl4CompiledIr mtl4GetOrCompileIr(const uint8_t* ir, size_t irSize, GpuResult* result);

Mtl4Function mtl4CreateFunction(Mtl4CompiledIr* function, const void* constants, size_t constantsSize, NSString* name, GpuResult* result);

Mtl4Pipeline mtl4CreateComputePipeline(Mtl4Function function, GpuResult* result);
Mtl4Pipeline mtl4CreateGraphicsPipeline(Mtl4Function vertex, Mtl4Function fragment, GpuResult* result);
Mtl4Pipeline mtl4CreateMeshletPipeline(Mtl4Function meshlet, Mtl4Function fragment, GpuResult* result);

Mtl4PipelineMetadata* mtl4AcquirePipelineMetadataFrom(Mtl4Pipeline pipeline);
void mtl4ReleasePipelineMetadata(void);

bool mtl4IsPipelineScheduledForDeletion(Mtl4Pipeline pipeline);

// NOTE: Requires external deletion lock on gMtl4PipelineStorage.sync
//	Please, remove related pipelines before removing functions
void mtl4DestroyFunction(Mtl4Function function);
// NOTE: Requires external deletion lock on gMtl4PipelineStorage.sync
void mtl4DestroyPipeline(Mtl4Pipeline pipeline);

inline Mtl4Pipeline mtl4GpuPipelineToHandle(GpuPipeline pipeline) {
	return *(Mtl4Pipeline*)&pipeline;
}

inline GpuPipeline mtl4HandleToGpuPipeline(Mtl4Pipeline handle) {
	return *(GpuPipeline*)&handle;
}

template <>
struct CmnTypeTraits<Mtl4Ir> {
	static bool eq(const Mtl4Ir& left, const Mtl4Ir& right) {
		if (left.size != right.size) {
			return false;
		}

		return memcmp(&left, &right, left.size) == 0;
	}

	static size_t hash(const Mtl4Ir& value) {
		(void)value;

		size_t hash = 0xFBC8C0FFEEBABE49;
		for (size_t i = 0; i < (value.size / 8); i++) {
			uint64_t word = *(uint64_t*)&value.bytes[i];

			hash = hash ^ cmnHashInteger64(word);
		}

		return hash;
	}

	static CmnCmp cmp(const Mtl4Ir& left, const Mtl4Ir& right) {
		(void)left; (void)right;
		assert(false && "Mtl4Ir does not support the cmp operation.");
	}
};

#endif // MTL4_PIPELINE_H

