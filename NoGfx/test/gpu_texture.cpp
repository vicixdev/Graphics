#include "gpu_common.h"

#include <cstdlib>
#include <pthread.h>
#include <sched.h>
#include <lib/common/atomic.h>

void checkGpuTextureSizeAlign(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	GpuTextureDesc desc = makeDefaultTextureDesc();
	GpuTextureSizeAlign sizeAlign = gpuTextureSizeAlign(&desc, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, sizeAlign.size > 0);
	TEST_ASSERT(test, sizeAlign.align > 0);

	gpuDeinit();
}

void checkGpuTextureSizeAlignInvalidDesc(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	GpuTextureSizeAlign sizeAlign = gpuTextureSizeAlign(nullptr, &result);

	TEST_ASSERT(test, result == GPU_INVALID_PARAMETERS);
	TEST_ASSERT(test, sizeAlign.size == 0);
	TEST_ASSERT(test, sizeAlign.align == 0);

	gpuDeinit();
}

void checkGpuCreateTexture(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	GpuTextureDesc desc = makeDefaultTextureDesc();
	GpuTextureSizeAlign sizeAlign = gpuTextureSizeAlign(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, sizeAlign.size > 0);

	void* ptrGpu = gpuMalloc(sizeAlign.size, sizeAlign.align, GPU_MEMORY_GPU, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, ptrGpu != nullptr);

	GpuTexture texture = gpuCreateTexture(&desc, ptrGpu, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, texture != 0);

	gpuFree(ptrGpu);
	gpuDeinit();
}

void checkGpuCreateTextureOnCpuAllocation(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	GpuTextureDesc desc = makeDefaultTextureDesc();
	GpuTextureSizeAlign sizeAlign = gpuTextureSizeAlign(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, sizeAlign.size > 0);

	void* ptrCpu = gpuMalloc(sizeAlign.size, sizeAlign.align, GPU_MEMORY_DEFAULT, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, ptrCpu != nullptr);

	GpuTexture texture = gpuCreateTexture(&desc, ptrCpu, &result);

	TEST_ASSERT(test, result == GPU_ALLOCATION_MEMORY_IS_CPU);
	TEST_ASSERT(test, texture == 0);

	gpuFree(ptrCpu);
	gpuDeinit();
}

void checkGpuCreateTextureInvalidDesc(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	void* ptrGpu = gpuMalloc(1024, 16, GPU_MEMORY_GPU, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, ptrGpu != nullptr);

	GpuTexture texture = gpuCreateTexture(nullptr, ptrGpu, &result);

	TEST_ASSERT(test, result == GPU_INVALID_PARAMETERS);
	TEST_ASSERT(test, texture == 0);

	gpuFree(ptrGpu);
	gpuDeinit();
}

void checkGpuTextureViewDescriptor(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	GpuTextureDesc textureDesc = makeDefaultTextureDesc();
	GpuTextureSizeAlign sizeAlign = gpuTextureSizeAlign(&textureDesc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	void* ptrGpu = gpuMalloc(sizeAlign.size, sizeAlign.align, GPU_MEMORY_GPU, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuTexture texture = gpuCreateTexture(&textureDesc, ptrGpu, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, texture != 0);

	GpuViewDesc viewDesc = {};
	viewDesc.format = GPU_FORMAT_RGBA8_UNORM;
	viewDesc.baseMip = 0;
	viewDesc.mipCount = 1;
	viewDesc.baseLayer = 0;
	viewDesc.layerCount = 1;

	GpuTextureDescriptor descriptor = gpuTextureViewDescriptor(texture, &viewDesc, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, descriptor.data[0] != 0);

	gpuFree(ptrGpu);
	gpuDeinit();
}

void checkGpuRWTextureViewDescriptor(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	GpuTextureDesc textureDesc = makeDefaultTextureDesc();
	GpuTextureSizeAlign sizeAlign = gpuTextureSizeAlign(&textureDesc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	void* ptrGpu = gpuMalloc(sizeAlign.size, sizeAlign.align, GPU_MEMORY_GPU, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuTexture texture = gpuCreateTexture(&textureDesc, ptrGpu, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, texture != 0);

	GpuViewDesc viewDesc = {};
	viewDesc.format = GPU_FORMAT_RGBA8_UNORM;
	viewDesc.baseMip = 0;
	viewDesc.mipCount = 1;
	viewDesc.baseLayer = 0;
	viewDesc.layerCount = 1;

	GpuTextureDescriptor descriptor = gpuRWTextureViewDescriptor(texture, &viewDesc, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, descriptor.data[0] != 0);

	gpuFree(ptrGpu);
	gpuDeinit();
}

void checkGpuTextureViewDescriptorInvalidTexture(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	GpuViewDesc viewDesc = {};
	viewDesc.format = GPU_FORMAT_RGBA8_UNORM;
	viewDesc.baseMip = 0;
	viewDesc.mipCount = 1;
	viewDesc.baseLayer = 0;
	viewDesc.layerCount = 1;

	GpuTextureDescriptor descriptor = gpuTextureViewDescriptor((GpuTexture)0, &viewDesc, &result);

	TEST_ASSERT(test, result == GPU_NO_SUCH_TEXTURE_FOUND);
	TEST_ASSERT(test, descriptor.data[0] == 0);

	gpuDeinit();
}

void checkGpuTextureViewDescriptorInvalidDesc(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	GpuTextureDesc textureDesc = makeDefaultTextureDesc();
	GpuTextureSizeAlign sizeAlign = gpuTextureSizeAlign(&textureDesc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	void* ptrGpu = gpuMalloc(sizeAlign.size, sizeAlign.align, GPU_MEMORY_GPU, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuTexture texture = gpuCreateTexture(&textureDesc, ptrGpu, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, texture != 0);

	GpuTextureDescriptor descriptor = gpuTextureViewDescriptor(texture, nullptr, &result);

	TEST_ASSERT(test, result == GPU_INVALID_PARAMETERS);
	TEST_ASSERT(test, descriptor.data[0] == 0);

	gpuFree(ptrGpu);
	gpuDeinit();
}

typedef struct GpuTextureCreatorContext {
	GpuTextureDesc desc;

	void* ptrGpu;
	GpuTexture texture;
	GpuResult sizeAlignResult;
	GpuResult allocationResult;
	GpuResult createResult;
	uint32_t created;
} GpuTextureCreatorContext;

typedef struct GpuTextureDestroyerContext {
	GpuTextureCreatorContext* creator;
	GpuResult descriptorResult;
	GpuTextureDescriptor descriptor;
	uint32_t destroyed;
} GpuTextureDestroyerContext;

static void* gpuTextureCreatorThreadProc(void* ptr) {
	GpuTextureCreatorContext* context = (GpuTextureCreatorContext*)ptr;

	GpuTextureSizeAlign sizeAlign = gpuTextureSizeAlign(&context->desc, &context->sizeAlignResult);
	if (context->sizeAlignResult != GPU_SUCCESS) {
		cmnAtomicStore(&context->created, 1u, CMN_RELEASE);
		return nullptr;
	}

	context->ptrGpu = gpuMalloc(sizeAlign.size, sizeAlign.align, GPU_MEMORY_GPU, &context->allocationResult);
	if (context->allocationResult != GPU_SUCCESS || context->ptrGpu == nullptr) {
		cmnAtomicStore(&context->created, 1u, CMN_RELEASE);
		return nullptr;
	}

	context->texture = gpuCreateTexture(&context->desc, context->ptrGpu, &context->createResult);
	cmnAtomicStore(&context->created, 1u, CMN_RELEASE);

	return nullptr;
}

static void* gpuTextureDestroyerThreadProc(void* ptr) {
	GpuTextureDestroyerContext* context = (GpuTextureDestroyerContext*)ptr;

	while (cmnAtomicLoad(&context->creator->created, CMN_ACQUIRE) == 0u) {
		sched_yield();
	}

	if (context->creator->createResult == GPU_SUCCESS && context->creator->texture != 0 && context->creator->ptrGpu != nullptr) {
		GpuViewDesc viewDesc = {};
		viewDesc.format = context->creator->desc.format;
		viewDesc.baseMip = 0;
		viewDesc.mipCount = 1;
		viewDesc.baseLayer = 0;
		viewDesc.layerCount = 1;

		context->descriptor = gpuTextureViewDescriptor(context->creator->texture, &viewDesc, &context->descriptorResult);
		gpuFree(context->creator->ptrGpu);
	}

	cmnAtomicStore(&context->destroyed, 1u, CMN_RELEASE);
	return nullptr;
}

void checkGpuTextureCreatedAndBackingFreedOnDifferentThreads(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	GpuTextureCreatorContext creatorContext = {};
	creatorContext.desc = makeDefaultTextureDesc();

	GpuTextureDestroyerContext destroyerContext = {};
	destroyerContext.creator = &creatorContext;

	pthread_t creatorThread;
	int createResult = pthread_create(&creatorThread, nullptr, gpuTextureCreatorThreadProc, &creatorContext);
	TEST_ASSERT(test, createResult == 0);

	pthread_t destroyerThread;
	createResult = pthread_create(&destroyerThread, nullptr, gpuTextureDestroyerThreadProc, &destroyerContext);
	TEST_ASSERT(test, createResult == 0);

	int joinResult = pthread_join(creatorThread, nullptr);
	TEST_ASSERT(test, joinResult == 0);

	joinResult = pthread_join(destroyerThread, nullptr);
	TEST_ASSERT(test, joinResult == 0);

	TEST_ASSERT(test, creatorContext.sizeAlignResult == GPU_SUCCESS);
	TEST_ASSERT(test, creatorContext.allocationResult == GPU_SUCCESS);
	TEST_ASSERT(test, creatorContext.createResult == GPU_SUCCESS);
	TEST_ASSERT(test, creatorContext.texture != 0);
	TEST_ASSERT(test, destroyerContext.descriptorResult == GPU_SUCCESS);
	TEST_ASSERT(test, destroyerContext.descriptor.data[0] != 0);
	TEST_ASSERT(test, cmnAtomicLoad(&destroyerContext.destroyed, CMN_ACQUIRE) == 1u);

	gpuDeinit();
}

typedef struct GpuTextureStressThreadContext {
	GpuStressGate* gate;
	GpuTextureDesc desc;
	GpuTextureSizeAlign sizeAlign;
	size_t iterations;
	uint32_t completed;
	uint32_t failed;
} GpuTextureStressThreadContext;


static void* gpuTextureStressThreadProc(void* ptr) {
	GpuTextureStressThreadContext* context = (GpuTextureStressThreadContext*)ptr;

	gpuWaitForStressStart(context->gate);

	for (size_t i = 0; i < context->iterations; i++) {
		GpuResult allocationResult = GPU_GENERAL_ERROR;
		void* ptrGpu = gpuMalloc(context->sizeAlign.size, context->sizeAlign.align, GPU_MEMORY_GPU, &allocationResult);
		if (allocationResult != GPU_SUCCESS || ptrGpu == nullptr) {
			context->failed = 1u;
			context->completed = 1u;
			return nullptr;
		}

		GpuResult textureResult = GPU_GENERAL_ERROR;
		GpuTexture texture = gpuCreateTexture(&context->desc, ptrGpu, &textureResult);
		if (textureResult != GPU_SUCCESS || texture == 0) {
			gpuFree(ptrGpu);
			context->failed = 1u;
			context->completed = 1u;
			return nullptr;
		}

		GpuViewDesc viewDesc = {};
		viewDesc.format = context->desc.format;
		viewDesc.baseMip = 0;
		viewDesc.mipCount = 1;
		viewDesc.baseLayer = 0;
		viewDesc.layerCount = 1;

		GpuResult viewResult = GPU_GENERAL_ERROR;
		GpuTextureDescriptor descriptor = gpuTextureViewDescriptor(texture, &viewDesc, &viewResult);
		if (viewResult != GPU_SUCCESS || descriptor.data[0] == 0) {
			gpuFree(ptrGpu);
			context->failed = 1u;
			context->completed = 1u;
			return nullptr;
		}

		GpuResult rwViewResult = GPU_GENERAL_ERROR;
		descriptor = gpuRWTextureViewDescriptor(texture, &viewDesc, &rwViewResult);
		if (rwViewResult != GPU_SUCCESS || descriptor.data[0] == 0) {
			gpuFree(ptrGpu);
			context->failed = 1u;
			context->completed = 1u;
			return nullptr;
		}

		gpuFree(ptrGpu);
	}

	context->completed = 1u;
	return nullptr;
}

static void runGpuTextureStress(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	GpuTextureDesc desc = makeDefaultTextureDesc();
	GpuTextureSizeAlign sizeAlign = gpuTextureSizeAlign(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, sizeAlign.size > 0);
	TEST_ASSERT(test, sizeAlign.align > 0);

	const size_t threadCount = 6;
	const size_t iterations = 64;

	GpuStressGate gate = {};
	GpuTextureStressThreadContext contexts[threadCount] = {};
	pthread_t threads[threadCount];

	for (size_t i = 0; i < threadCount; i++) {
		contexts[i].gate = &gate;
		contexts[i].desc = desc;
		contexts[i].sizeAlign = sizeAlign;
		contexts[i].iterations = iterations;

		int createResult = pthread_create(&threads[i], nullptr, gpuTextureStressThreadProc, &contexts[i]);
		TEST_ASSERT(test, createResult == 0);
	}

	waitForGateReady(&gate, threadCount);
	cmnAtomicStore(&gate.start, 1u, CMN_RELEASE);

	for (size_t i = 0; i < threadCount; i++) {
		int joinResult = pthread_join(threads[i], nullptr);
		TEST_ASSERT(test, joinResult == 0);
		TEST_ASSERT(test, contexts[i].completed == 1u);
		TEST_ASSERT(test, contexts[i].failed == 0u);
	}

	gpuDeinit();
}

void checkGpuConcurrentTextureStress(Test* test) {
	runGpuTextureStress(test);
}

void checkGpuDeferredTextureDeletionThresholdFlush(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	GpuTextureDesc desc = makeDefaultTextureDesc();
	GpuTextureSizeAlign sizeAlign = gpuTextureSizeAlign(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, sizeAlign.size > 0);
	TEST_ASSERT(test, sizeAlign.align > 0);

	const size_t textureCount = 136;

	void** allocations = (void**)malloc(sizeof(void*) * textureCount);
	GpuTexture* textures = (GpuTexture*)malloc(sizeof(GpuTexture) * textureCount);
	if (allocations == nullptr || textures == nullptr) {
		testOutOfMemory(test);
	}

	for (size_t i = 0; i < textureCount; i++) {
		allocations[i] = gpuMalloc(sizeAlign.size, sizeAlign.align, GPU_MEMORY_GPU, &result);
		TEST_ASSERT(test, result == GPU_SUCCESS);
		TEST_ASSERT(test, allocations[i] != nullptr);

		textures[i] = gpuCreateTexture(&desc, allocations[i], &result);
		TEST_ASSERT(test, result == GPU_SUCCESS);
		TEST_ASSERT(test, textures[i] != 0);
	}

	GpuTexture firstTexture = textures[0];
	for (size_t i = 0; i < textureCount; i++) {
		gpuFree(allocations[i]);
	}

	GpuViewDesc viewDesc = {};
	viewDesc.format = desc.format;
	viewDesc.baseMip = 0;
	viewDesc.mipCount = 1;
	viewDesc.baseLayer = 0;
	viewDesc.layerCount = 1;

	GpuTextureDescriptor descriptor = gpuTextureViewDescriptor(firstTexture, &viewDesc, &result);
	TEST_ASSERT(test, result == GPU_NO_SUCH_TEXTURE_FOUND);
	TEST_ASSERT(test, descriptor.data[0] == 0);

	free(allocations);
	free(textures);
	gpuDeinit();
}
