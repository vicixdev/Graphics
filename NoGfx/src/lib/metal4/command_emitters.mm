#include "command_emitters.h"

#include <lib/metal4/context.h>
#include <lib/metal4/allocation.h>
#include <lib/metal4/events.h>
#include <lib/metal4/shader/acquire_icb_range.h>
#include <lib/metal4/shader/prep_multidrawindirect.h>

const uint32_t MTL4_ACQUIRE_ICB_RANGE_CONSTANTS[1] = {
	/*icbBufferSize=*/	16384,
};
uint32_t MTL4_ACQUIRE_ICB_RANGE_GROUP_SIZE[3] = { 1, 1, 1 };

uint32_t MTL4_PREPARE_MULTIDRAW_ICBS_GROUP_SIZE[3] = { 16384, 1, 1 };

Mtl4CommandEmissionStorage gMtl4CommandEmissionStorage;

void mtl4InitCommandEmissionStorage(GpuResult* result) {

	GpuResult localResult;

	cmnCreateSemaphore(&gMtl4CommandEmissionStorage.contextsSemaphore, MTL4_MAX_COMMAND_EMITTERS);

	gMtl4CommandEmissionStorage.zeroBuffer = [gMtl4Context.device
		newBufferWithLength:1024
		options:MTLResourceStorageModePrivate
	];
	if (gMtl4CommandEmissionStorage.zeroBuffer == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
	}
	gMtl4CommandEmissionStorage.zeroBuffer.label = @"gMtl4CommandEmissionStorage.zeroBuffer";
	mtl4AddAllocationToResidencySet(gMtl4CommandEmissionStorage.zeroBuffer);


	MTLIndirectCommandBufferDescriptor* icbDesc = [[MTLIndirectCommandBufferDescriptor new] autorelease];
	icbDesc.commandTypes = MTLIndirectCommandTypeDrawIndexed;
	icbDesc.inheritCullMode = YES;
	icbDesc.inheritDepthStencilState = YES;
	icbDesc.inheritDepthBias = YES;
	icbDesc.inheritDepthClipMode = YES;
	icbDesc.inheritPipelineState = YES;
	icbDesc.inheritFrontFacingWinding = YES;
	icbDesc.inheritTriangleFillMode = YES;
	icbDesc.inheritBuffers = NO;
	icbDesc.maxVertexBufferBindCount = 1;
	icbDesc.maxFragmentBufferBindCount = 2;

	gMtl4CommandEmissionStorage.icbBuffer = [gMtl4Context.device
		newIndirectCommandBufferWithDescriptor:icbDesc
		maxCommandCount:16384
		options:MTLResourceStorageModePrivate];
	if (gMtl4CommandEmissionStorage.icbBuffer == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
	}
	gMtl4CommandEmissionStorage.icbBuffer.label = @"gMtl4CommandEmissionStorage.icbBuffer";
	mtl4AddAllocationToResidencySet(gMtl4CommandEmissionStorage.icbBuffer);

	gMtl4CommandEmissionStorage.firstFreeIcbIndex = [gMtl4Context.device
		newBufferWithLength:sizeof(uint32_t)
		options:MTLResourceStorageModePrivate];
	if (gMtl4CommandEmissionStorage.firstFreeIcbIndex == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
	}
	gMtl4CommandEmissionStorage.firstFreeIcbIndex.label = @"gMtl4CommandEmissionStorage.firstFreeIcbIndex";
	mtl4AddAllocationToResidencySet(gMtl4CommandEmissionStorage.firstFreeIcbIndex);


	GpuPipeline acquireIcbRange = gpuCreateComputePipeline(
		gMtl4AcquireIcbRangeBytecode, sizeof(gMtl4AcquireIcbRangeBytecode),
		MTL4_ACQUIRE_ICB_RANGE_CONSTANTS, sizeof(MTL4_ACQUIRE_ICB_RANGE_CONSTANTS),
		MTL4_ACQUIRE_ICB_RANGE_GROUP_SIZE,
		&localResult);
	assert(localResult == GPU_SUCCESS && "The builtin `acquireIcbRange` pipeline failed to compile.");
	gMtl4CommandEmissionStorage.acquireIcbRange = mtl4GpuPipelineToHandle(acquireIcbRange);

	GpuPipeline prepareMultiDrawIcbs = gpuCreateComputePipeline(
		gMtl4PrepareMultidrawIndirectIcbsBytecode, sizeof(gMtl4PrepareMultidrawIndirectIcbsBytecode),
		NULL, 0,
		MTL4_PREPARE_MULTIDRAW_ICBS_GROUP_SIZE,
		&localResult);
	assert(localResult == GPU_SUCCESS && "The builtin `prepareMultidrawIndirectIcbs` pipeline failed to compile.");
	gMtl4CommandEmissionStorage.prepareMultidrawIcbs = mtl4GpuPipelineToHandle(prepareMultiDrawIcbs);


	for (size_t i = 0; i < MTL4_MAX_COMMAND_EMITTERS; i++) {
		mtl4InitCommandEmissionContext(&gMtl4CommandEmissionStorage.contexts[i], &localResult);
		if (localResult != GPU_SUCCESS) {
			CMN_SET_RESULT(result, localResult);
			return;
		}
	}

	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4FiniCommandEmissionStorage(void) {
	for (size_t i = 0; i < MTL4_MAX_COMMAND_EMITTERS; i++) {
		mtl4FiniCommandEmissionContext(&gMtl4CommandEmissionStorage.contexts[i]);
	}

	if (gMtl4CommandEmissionStorage.zeroBuffer != nil) {
		[gMtl4CommandEmissionStorage.zeroBuffer release];
	}

	if (gMtl4CommandEmissionStorage.firstFreeIcbIndex != nil) {
		[gMtl4CommandEmissionStorage.firstFreeIcbIndex release];
	}

	if (gMtl4CommandEmissionStorage.icbBuffer != nil) {
		[gMtl4CommandEmissionStorage.icbBuffer release];
	}

	gpuFreePipeline(mtl4HandleToGpuPipeline(gMtl4CommandEmissionStorage.acquireIcbRange));
	gpuFreePipeline(mtl4HandleToGpuPipeline(gMtl4CommandEmissionStorage.prepareMultidrawIcbs));

	gMtl4CommandEmissionStorage = {};
}

void mtl4InitCommandEmissionContext(Mtl4CommandEmissionContext* context, GpuResult* result) {
	context->bumpBuffer = [gMtl4Context.device
		newBufferWithLength:1024*1024
		options:MTLResourceStorageModeShared | MTLResourceCPUCacheModeWriteCombined
	];
	if (context->bumpBuffer == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
	}
	context->bumpBufferSize = 1024 * 1024;
	mtl4AddAllocationToResidencySet(context->bumpBuffer);


	context->commandAllocator = [gMtl4Context.device newCommandAllocator];
	if (context->commandAllocator == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_GPU_MEMORY);
		return;
	}


	MTL4ArgumentTableDescriptor* computeArgumentTableDesc = [[MTL4ArgumentTableDescriptor new] autorelease];
	computeArgumentTableDesc.maxBufferBindCount = 1;
	computeArgumentTableDesc.maxSamplerStateBindCount = 0;
	computeArgumentTableDesc.maxTextureBindCount = 0;

	MTL4ArgumentTableDescriptor* vertexArgumentTableDesc = [[MTL4ArgumentTableDescriptor new] autorelease];
	vertexArgumentTableDesc.maxBufferBindCount = 1;
	vertexArgumentTableDesc.maxSamplerStateBindCount = 0;
	vertexArgumentTableDesc.maxTextureBindCount = 0;

	MTL4ArgumentTableDescriptor* fragmentArgumentTableDesc = [[MTL4ArgumentTableDescriptor new] autorelease];
	fragmentArgumentTableDesc.maxBufferBindCount = 2;
	fragmentArgumentTableDesc.maxSamplerStateBindCount = 0;
	fragmentArgumentTableDesc.maxTextureBindCount = 0;

	context->computeArgumentTable = [gMtl4Context.device
		newArgumentTableWithDescriptor:computeArgumentTableDesc
		error:nullptr];
	if (context->computeArgumentTable == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	context->vertexArgumentTable = [gMtl4Context.device
		newArgumentTableWithDescriptor:vertexArgumentTableDesc
		error:nullptr];
	if (context->vertexArgumentTable == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}

	context->fragmentArgumentTable = [gMtl4Context.device
		newArgumentTableWithDescriptor:fragmentArgumentTableDesc
		error:nullptr];
	if (context->fragmentArgumentTable == nil) {
		CMN_SET_RESULT(result, GPU_OUT_OF_CPU_MEMORY);
		return;
	}


	CMN_SET_RESULT(result, GPU_SUCCESS);
}

void mtl4FiniCommandEmissionContext(Mtl4CommandEmissionContext* context) {
	if (context->bumpBuffer != nil) {
		[context->bumpBuffer release];
	}

	if (context->commandAllocator != nil) {
		[context->commandAllocator release];
	}

	if (context->computeArgumentTable != nil) {
		[context->computeArgumentTable release];
	}

	if (context->vertexArgumentTable != nil) {
		[context->vertexArgumentTable release];
	}

	if (context->fragmentArgumentTable != nil) {
		[context->fragmentArgumentTable release];
	}
}

Mtl4CommandEmissionContext* mtl4AcquireCommandEmissionContext(Mtl4Queue queue) {
	cmnSemaphoreWait(&gMtl4CommandEmissionStorage.contextsSemaphore);

	size_t index;
	for (;;) {
		index = cmnAtomicAdd(&gMtl4CommandEmissionStorage.firstFreeContextIndex, 1UL) % MTL4_MAX_COMMAND_EMITTERS;

		if (!cmnAtomicExchange(&gMtl4CommandEmissionStorage.contexts[index].inUse, true)) {
			break;
		}
	}

	Mtl4CommandEmissionContext* context =  &gMtl4CommandEmissionStorage.contexts[index];

	// TODO: Use the queue argument.
	context->queue = mtl4Queue();
	[context->queue addResidencySet:gMtl4AllocationStorage.residencySet];

	return context;
}

void mtl4ReleaseCommandEmissionContext(Mtl4CommandEmissionContext* context) {
	cmnAtomicLoad(&context->inUse);

	cmnSemaphorePost(&gMtl4CommandEmissionStorage.contextsSemaphore);
}


