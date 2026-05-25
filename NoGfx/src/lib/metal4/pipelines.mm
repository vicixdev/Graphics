#include "pipelines.h"

#include <Foundation/Foundation.h>
#include <dispatch/dispatch.h>

#include <lib/common/heap_allocator.h>
#include <lib/common/scoped_nsautoreleasepool.h>
#include <lib/metal4/context.h>
#include <lib/metal4/deletion_manager.h>
#include <lib/metal4/tables.h>

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
	uint32_t groupSize[3],
	GpuResult* result
) {
	CmnScopedNSAutoreleasePool pool;

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
	
	Mtl4Pipeline pipeline = mtl4CreateComputePipeline(function, groupSize, &localResult);
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
	const GpuRasterDesc* desc,
	GpuResult* result
) {
	CmnScopedNSAutoreleasePool pool;

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
	
	Mtl4Pipeline pipeline = mtl4CreateGraphicsPipeline(vertexFunction, fragmentFunction, desc, &localResult);
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
	const GpuRasterDesc* desc,
	GpuResult* result
) {
	CmnScopedNSAutoreleasePool pool;

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
	
	Mtl4Pipeline pipeline = mtl4CreateMeshletPipeline(meshletFunction, fragmentFunction, desc, &localResult);
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
		// TODO: Do not leak the constant values object.
		MTLFunctionConstantValues* constantValues = [MTLFunctionConstantValues new];

		for (size_t i = 0; i < (constantsSize / 4); i++) {
			[constantValues setConstantValue:constants type:MTLDataTypeUInt atIndex:i];
		}

		MTL4SpecializedFunctionDescriptor* functionDescriptor = [MTL4SpecializedFunctionDescriptor new];
		functionDescriptor.functionDescriptor	= baseDescriptor;
		functionDescriptor.constantValues	= constantValues;

		metadata.descriptor = functionDescriptor;
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return metadata;
}

Mtl4Pipeline mtl4CreateComputePipeline(Mtl4Function function, uint32_t groupSize[3], GpuResult* result) {
	
	CmnResult localResult;
	CmnScopedStorageSyncLockWrite guard(&gMtl4PipelineStorage.sync);

	MTL4ComputePipelineDescriptor* psoDesc = [[MTL4ComputePipelineDescriptor new] autorelease];
	psoDesc.computeFunctionDescriptor = function.descriptor;

	NSError* error;
	id<MTLComputePipelineState> pso = [gMtl4PipelineStorage.compiler
		newComputePipelineStateWithDescriptor:psoDesc
		compilerTaskOptions:nullptr
		error:&error];
	if (pso == nil) {
		printf("Failed to create compute pipeline state: %s\n", [[error localizedDescription] UTF8String]);

		CMN_SET_RESULT(result, GPU_PIPELINE_IR_VALIDATION_FAILED);
		return {};
	}

	Mtl4PipelineMetadata metadata = {};
	metadata.type			= MTL4_PIPELINE_COMPUTE;
	metadata.compute.pso		= pso;
	memcpy(metadata.compute.groupSize, groupSize, sizeof(uint32_t[3]));

	Mtl4Pipeline pipeline = cmnInsert(&gMtl4PipelineStorage.pipelines, metadata, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return {};
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return pipeline;
}

Mtl4Pipeline mtl4CreateGraphicsPipeline(Mtl4Function vertex, Mtl4Function fragment, const GpuRasterDesc* desc, GpuResult* result) {
	CmnResult localResult;
	CmnScopedStorageSyncLockWrite guard(&gMtl4PipelineStorage.sync);

	MTL4RenderPipelineDescriptor* pipelineDesc = [[MTL4RenderPipelineDescriptor new] autorelease];
	pipelineDesc.vertexFunctionDescriptor = vertex.descriptor;
	pipelineDesc.fragmentFunctionDescriptor = fragment.descriptor;
	pipelineDesc.rasterSampleCount = desc->sampleCount;
	pipelineDesc.alphaToCoverageState = desc->alphaToCoverage ? MTL4AlphaToCoverageStateEnabled : MTL4AlphaToCoverageStateDisabled;
	pipelineDesc.inputPrimitiveTopology = MTLPrimitiveTopologyClassTriangle;
	pipelineDesc.supportIndirectCommandBuffers = MTL4IndirectCommandBufferSupportStateEnabled;

	for (size_t i = 0; i < desc->colorTargetCount; i++) {
		const GpuColorTarget* colorTarget = &desc->colorTargets[i];

		MTL4RenderPipelineColorAttachmentDescriptor* colorAttachment = [[MTL4RenderPipelineColorAttachmentDescriptor new] autorelease];
		colorAttachment.pixelFormat = gMtl4GpuToMtlFormat[colorTarget->format];
		colorAttachment.writeMask = colorTarget->writeMask;
		colorAttachment.blendingState = MTL4BlendStateUnspecialized;
		
		pipelineDesc.colorAttachments[i] = colorAttachment;
	}

	if (desc->blendstate != nullptr && desc->colorTargetCount > 0) {
		pipelineDesc.colorAttachments[0].blendingState = MTL4BlendStateEnabled;
		pipelineDesc.colorAttachments[0].rgbBlendOperation = gMtl4GpuBlendToMtlBlendOperation[desc->blendstate->colorOp];
		pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = gMtl4GpuFactorToMtlBlendFactor[desc->blendstate->srcColorFactor];
		pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = gMtl4GpuFactorToMtlBlendFactor[desc->blendstate->dstColorFactor];
		pipelineDesc.colorAttachments[0].alphaBlendOperation = gMtl4GpuBlendToMtlBlendOperation[desc->blendstate->alphaOp];
		pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = gMtl4GpuFactorToMtlBlendFactor[desc->blendstate->srcAlphaFactor];
		pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = gMtl4GpuFactorToMtlBlendFactor[desc->blendstate->dstAlphaFactor];
		pipelineDesc.colorAttachments[0].writeMask = desc->blendstate->colorWriteMask;
	}

	NSError* error;
	id<MTLRenderPipelineState> pso = [gMtl4PipelineStorage.compiler
		newRenderPipelineStateWithDescriptor:pipelineDesc
		compilerTaskOptions:nil
		error:&error];
	if (pso == nil) {
		printf("Failed to create graphics pipeline state: %s\n", [[error localizedDescription] UTF8String]);

		CMN_SET_RESULT(result, GPU_PIPELINE_IR_VALIDATION_FAILED);
		return {};
	}

	Mtl4PipelineMetadata metadata = {};
	metadata.type = MTL4_PIPELINE_GRAPHICS;
	metadata.graphics.pso = pso;
	metadata.graphics.desc = *desc;

	Mtl4Pipeline pipeline = cmnInsert(&gMtl4PipelineStorage.pipelines, metadata, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return {};
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
	return pipeline;
}

Mtl4Pipeline mtl4CreateMeshletPipeline(Mtl4Function meshlet, Mtl4Function fragment, const GpuRasterDesc* desc, GpuResult* result) {
	(void)meshlet;
	(void)fragment;
	(void)desc;
	(void)result;

	CMN_SET_RESULT(result, GPU_UNSUPPORTED_OPERATION);
	return {};
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
			[metadata.graphics.pso release];

			break;
		}
		case MTL4_PIPELINE_MESHLET: {
			[metadata.meshlet.pso release];

			break;
		}
	}

	cmnRemove(&gMtl4PipelineStorage.pipelines, pipeline);
}

