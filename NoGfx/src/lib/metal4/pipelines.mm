#include "pipelines.h"

#include <dispatch/dispatch.h>

#include <lib/common/heap_allocator.h>
#include <lib/metal4/context.h>
#include <lib/metal4/deletion_manager.h>

Mtl4PipelineStorage gMtl4PipelineStorage;

void mtl4InitPipelineStorage(GpuResult* result) {
	CmnResult localResult;
	MTL4CompilerDescriptor* compilerDescriptor = nil;

	gMtl4PipelineStorage = {};

	gMtl4PipelineStorage.page = cmnCreatePage(32 * 1024 * 1024, CMN_PAGE_READABLE | CMN_PAGE_WRITABLE, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	gMtl4PipelineStorage.arena = cmnPageToArena(gMtl4PipelineStorage.page);

	CmnAllocator allocator = cmnArenaAllocator(&gMtl4PipelineStorage.arena);

	cmnCreateHashMap(&gMtl4PipelineStorage.compiledIrs, 0, {}, cmnHeapAllocator(), &localResult);
	if (localResult != CMN_SUCCESS) {
		mtl4FiniPipelineStorage();

		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	cmnCreateHandleMap(&gMtl4PipelineStorage.pipelines, allocator, {}, &localResult);
	if (localResult != CMN_SUCCESS) {
		mtl4FiniPipelineStorage();

		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	compilerDescriptor = [MTL4CompilerDescriptor new];
	defer ([compilerDescriptor release]);

	compilerDescriptor.label = @"No Graphics compiler descriptor";

	gMtl4PipelineStorage.compiler = [gMtl4Context.device newCompilerWithDescriptor:compilerDescriptor error:nil];
	if (gMtl4PipelineStorage.compiler == nil) {
		mtl4FiniPipelineStorage();

		CMN_SET_RESULT(result, GPU_GENERAL_ERROR);
		return;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return;
}

void mtl4FiniPipelineStorage(void) {
	// TODO: Free all the allocated resources for the pipeline metadata.

	if (gMtl4PipelineStorage.compiler != nil) {
		[gMtl4PipelineStorage.compiler release];
	}

	cmnDestroyHashMap(&gMtl4PipelineStorage.compiledIrs);
	cmnDestroyPage(gMtl4PipelineStorage.page);

	gMtl4PipelineStorage = {};
}

GpuPipeline mtl4CreateComputePipeline(
	const uint8_t* ir, size_t irSize,
	const void* constants, size_t constantsSize,
	GpuResult* result
) {
	GpuResult localResult;

	Mtl4CompiledIr compiledIr = mtl4GetOrCompileIr(ir, irSize, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return {};
	}

	Mtl4Function function = mtl4CreateFunction(&compiledIr, constants, constantsSize, @"main", &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return {};
	}
	
	Mtl4Pipeline pipeline = mtl4CreateComputePipeline(function, &localResult);
	if (localResult != GPU_SUCCESS) {
		mtl4DestroyFunction(function);

		CMN_SET_RESULT(result, localResult);
		return {};
	}

	CMN_SET_RESULT(result, localResult);
	return mtl4HandleToGpuPipeline(pipeline);
}

GpuPipeline mtl4CreateRenderPipeline(
	const uint8_t* vertexIr, size_t vertexIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* vertexConstants, size_t vertexConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	GpuResult* result
) {
	GpuResult localResult;

	Mtl4CompiledIr compiledVertexIr = mtl4GetOrCompileIr(vertexIr, vertexIrSize, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return {};
	}

	Mtl4CompiledIr compiledFragmentIr = mtl4GetOrCompileIr(fragmentIr, fragmentIrSize, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return {};
	}

	Mtl4Function vertexFunction = mtl4CreateFunction(&compiledVertexIr, vertexConstants, vertexConstantsSize, @"main", &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return {};
	}

	Mtl4Function fragmentFunction = mtl4CreateFunction(&compiledFragmentIr, fragmentConstants, fragmentConstantsSize, @"main", &localResult);
	if (localResult != GPU_SUCCESS) {
		mtl4DestroyFunction(vertexFunction);

		CMN_SET_RESULT(result, localResult);
		return {};
	}
	
	Mtl4Pipeline pipeline = mtl4CreateGraphicsPipeline(vertexFunction, fragmentFunction, &localResult);
	if (localResult != GPU_SUCCESS) {
		mtl4DestroyFunction(vertexFunction);
		mtl4DestroyFunction(fragmentFunction);

		CMN_SET_RESULT(result, localResult);
		return {};
	}

	CMN_SET_RESULT(result, localResult);
	return mtl4HandleToGpuPipeline(pipeline);
}

GpuPipeline mtl4CreateMeshletPipeline(
	const uint8_t* meshletIr, size_t meshletIrSize,
	const uint8_t* fragmentIr, size_t fragmentIrSize,
	const void* meshletConstants, size_t meshletConstantsSize,
	const void* fragmentConstants, size_t fragmentConstantsSize,
	GpuResult* result
) {
	GpuResult localResult;

	Mtl4CompiledIr compiledMeshletIr = mtl4GetOrCompileIr(meshletIr, meshletIrSize, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return {};
	}

	Mtl4CompiledIr compiledFragmentIr = mtl4GetOrCompileIr(fragmentIr, fragmentIrSize, &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return {};
	}

	Mtl4Function meshletFunction = mtl4CreateFunction(&compiledMeshletIr, meshletConstants, meshletConstantsSize, @"main", &localResult);
	if (localResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return {};
	}

	Mtl4Function fragmentFunction = mtl4CreateFunction(&compiledFragmentIr, fragmentConstants, fragmentConstantsSize, @"main", &localResult);
	if (localResult != GPU_SUCCESS) {
		mtl4DestroyFunction(meshletFunction);

		CMN_SET_RESULT(result, localResult);
		return {};
	}
	
	Mtl4Pipeline pipeline = mtl4CreateMeshletPipeline(meshletFunction, fragmentFunction, &localResult);
	if (localResult != GPU_SUCCESS) {
		mtl4DestroyFunction(meshletFunction);
		mtl4DestroyFunction(fragmentFunction);

		CMN_SET_RESULT(result, localResult);
		return {};
	}

	CMN_SET_RESULT(result, localResult);
	return mtl4HandleToGpuPipeline(pipeline);
}

void mtl4FreePipeline(GpuPipeline pipeline) {
	Mtl4Pipeline handle = mtl4GpuPipelineToHandle(pipeline);
	{
		Mtl4PipelineMetadata* metadata = mtl4AcquirePipelineMetadataFrom(handle);
		if (metadata == nullptr) {
			return;
		}
		defer (mtl4ReleasePipelineMetadata());

		cmnAtomicStore(&metadata->scheduledForDeletion, true);

		mtl4SchedulePipelineForDeletion(handle);
	}

	mtl4CheckForResourceDeletion();
}

Mtl4CompiledIr mtl4CompileIr(const uint8_t* ir, size_t irSize, GpuResult* result) {
	dispatch_data_t data = dispatch_data_create(ir, irSize, dispatch_get_main_queue(), nullptr);

	NSError* error;
	id<MTLLibrary> library = [gMtl4Context.device newLibraryWithData:data error:&error];
	if (library == nil) {
		printf("Failed to compile shader ir: %s\n", [[error localizedDescription] UTF8String]);
		CMN_SET_RESULT(result, GPU_PIPELINE_IR_VALIDATION_FAILED);
		return {};
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return {
		/*library=*/	library,
	};
}

Mtl4CompiledIr mtl4GetOrCompileIr(const uint8_t* ir, size_t irSize, GpuResult* result) {
	CmnResult localResult;
	GpuResult localGpuResult;

	Mtl4Ir irr = {
		/*bytes=*/	ir,
		/*size=*/	irSize,
	};

	{
		CmnScopedStorageSyncLockRead guard(&gMtl4PipelineStorage.sync);

		bool didFindIr;
		Mtl4CompiledIr compiledIr = cmnGet(&gMtl4PipelineStorage.compiledIrs, irr, &didFindIr);
		if (didFindIr) {
			CMN_SET_RESULT(result, GPU_SUCCESS);
			return compiledIr;
		}
	}

	Mtl4CompiledIr newlyCompiledIr = mtl4CompileIr(ir, irSize, &localGpuResult);
	if (localGpuResult != GPU_SUCCESS) {
		CMN_SET_RESULT(result, localGpuResult);
		return {};
	}

	{
		CmnScopedStorageSyncLockWrite guard(&gMtl4PipelineStorage.sync);

		// NOTE: Another thread could have compiled the same Ir while this thread was compiling it. If so, let's
		//	use the other thread compiled ir.
		bool didFindIr;
		Mtl4CompiledIr cachedIr = cmnGet(&gMtl4PipelineStorage.compiledIrs, irr, &didFindIr);
		if (didFindIr) {
			[newlyCompiledIr.library release];

			CMN_SET_RESULT(result, GPU_SUCCESS);
			return cachedIr;
		}

		cmnInsert(&gMtl4PipelineStorage.compiledIrs, irr, newlyCompiledIr, &localResult);
		if (localResult != CMN_SUCCESS) {
			[newlyCompiledIr.library release];

			CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
			return {};
		}
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return newlyCompiledIr;
}

Mtl4Function mtl4CreateFunction(Mtl4CompiledIr* function, const void* constants, size_t constantsSize, NSString* name, GpuResult* result) {
	if (![[function->library functionNames] containsObject:name]) {
		CMN_SET_RESULT(result, GPU_PIPELINE_IR_VALIDATION_FAILED);
		return {};
	}
	
	MTL4LibraryFunctionDescriptor* baseDescriptor = [MTL4LibraryFunctionDescriptor new];
	baseDescriptor.library = function->library;
	baseDescriptor.name = name;

	Mtl4Function metadata = {};
	if (constants == nullptr || constantsSize == 0) {
		metadata.descriptor = baseDescriptor;
	} else {
		MTLFunctionConstantValues* constantValues = [MTLFunctionConstantValues new];

		for (size_t i = 0; i < (constantsSize / 8); i++) {
			[constantValues setConstantValue:constants type:MTLDataTypeULong atIndex:i];
		}

		MTL4SpecializedFunctionDescriptor* functionDescriptor = [MTL4SpecializedFunctionDescriptor new];
		functionDescriptor.functionDescriptor	= baseDescriptor;
		functionDescriptor.constantValues	= constantValues;

		[baseDescriptor release];
		[constantValues release];

		metadata.descriptor = functionDescriptor;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return metadata;
}

Mtl4Pipeline mtl4CreateComputePipeline(Mtl4Function function, GpuResult* result) {
	CmnResult localResult;
	CmnScopedStorageSyncLockWrite guard(&gMtl4PipelineStorage.sync);

	MTL4ComputePipelineDescriptor* psoDesc = [MTL4ComputePipelineDescriptor new];
	defer ([psoDesc release]);
	psoDesc.computeFunctionDescriptor = function.descriptor;

	id<MTLComputePipelineState> pso = [gMtl4PipelineStorage.compiler
		newComputePipelineStateWithDescriptor:psoDesc
		compilerTaskOptions:nullptr
		error:nullptr];
	if (pso == nil) {
		CMN_SET_RESULT(result, GPU_PIPELINE_IR_VALIDATION_FAILED);
		return {};
	}

	Mtl4PipelineMetadata metadata = {};
	metadata.type			= MTL4_PIPELINE_COMPUTE;
	metadata.compute.pso		= pso;

	Mtl4Pipeline pipeline = cmnInsert(&gMtl4PipelineStorage.pipelines, metadata, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return {};
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return pipeline;
}

Mtl4Pipeline mtl4CreateGraphicsPipeline(Mtl4Function vertex, Mtl4Function fragment, GpuResult* result) {
	CmnResult localResult;
	CmnScopedStorageSyncLockWrite guard(&gMtl4PipelineStorage.sync);

	Mtl4PipelineMetadata metadata = {};
	metadata.type = MTL4_PIPELINE_GRAPHICS;
	metadata.graphics.vertex = vertex;
	metadata.graphics.fragment = fragment;

	Mtl4Pipeline pipeline = cmnInsert(&gMtl4PipelineStorage.pipelines, metadata, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return {};
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return pipeline;
}

Mtl4Pipeline mtl4CreateMeshletPipeline(Mtl4Function meshlet, Mtl4Function fragment, GpuResult* result) {
	CmnResult localResult;
	CmnScopedStorageSyncLockWrite guard(&gMtl4PipelineStorage.sync);

	Mtl4PipelineMetadata metadata = {};
	metadata.type = MTL4_PIPELINE_MESHLET;
	metadata.meshlet.meshlet = meshlet;
	metadata.meshlet.fragment = fragment;

	Mtl4Pipeline pipeline = cmnInsert(&gMtl4PipelineStorage.pipelines, metadata, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return {};
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return pipeline;
}

Mtl4PipelineMetadata* mtl4AcquirePipelineMetadataFrom(Mtl4Pipeline pipeline) {
	bool wasHandleValid;
	Mtl4PipelineMetadata* metadata = cmnStorageSyncAcquireResource(
		&gMtl4PipelineStorage.pipelines,
		&gMtl4PipelineStorage.sync,
		pipeline,
		&wasHandleValid
	);
	if (!wasHandleValid) {
		return nullptr;
	}

	return metadata;
}

void mtl4ReleasePipelineMetadata(void) {
	cmnStorageSyncReleaseResource(&gMtl4PipelineStorage.sync);
}

bool mtl4IsPipelineScheduledForDeletion(Mtl4Pipeline pipeline) {
	Mtl4PipelineMetadata* metadata = mtl4AcquirePipelineMetadataFrom(pipeline);
	if (metadata == nullptr) {
		return false;
	}
	defer (mtl4ReleasePipelineMetadata());

	return cmnAtomicLoad(&metadata->scheduledForDeletion);
}

void mtl4DestroyFunction(Mtl4Function function) {
	[function.descriptor release];
}

void mtl4DestroyPipeline(Mtl4Pipeline pipeline) {
	bool wasHandleValid;
	Mtl4PipelineMetadata metadata = cmnGet(&gMtl4PipelineStorage.pipelines, pipeline, &wasHandleValid);
	if (!wasHandleValid) {
		return;
	}

	switch (metadata.type) {
		case MTL4_PIPELINE_COMPUTE: {
			[metadata.compute.pso release];

			break;
		}
		case MTL4_PIPELINE_GRAPHICS: {
			mtl4DestroyFunction(metadata.graphics.vertex);
			mtl4DestroyFunction(metadata.graphics.fragment);
			break;
		}
		case MTL4_PIPELINE_MESHLET: {
			mtl4DestroyFunction(metadata.meshlet.meshlet);
			mtl4DestroyFunction(metadata.meshlet.fragment);
			break;
		}
	}

	cmnRemove(&gMtl4PipelineStorage.pipelines, pipeline);
}

