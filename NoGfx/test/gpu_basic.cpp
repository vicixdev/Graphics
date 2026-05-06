void checkGpuInitAndDeinit(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuDeinit();
}

void checkGpuInvalidBackend(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectUnavailableBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);

	TEST_ASSERT(test, result == GPU_BACKEND_NOT_SUPPORTED);

	gpuDeinit();
}

void checkGpuEnumerateDevices(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;

	gpuEnumerateDevices(&devices, &count, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, count > 0);
	TEST_ASSERT(test, devices != nullptr);

	gpuDeinit();
}

void checkGpuSelectDevice(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;

	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuDeinit();
}

void checkGpuSelectInvalidDevice(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuSelectDevice((GpuDeviceId)999999, &result);
	TEST_ASSERT(test, result == GPU_INVALID_DEVICE);

	gpuDeinit();
}

void checkGpuDoubleDeviceSelection(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuSelectDevice(devices[0].identifier, &result);
	TEST_ASSERT(test, result == GPU_DEVICE_ALREADY_SELECTED);

	gpuDeinit();
}

void checkGpuMallocAndFree(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);

	void* ptr = gpuMalloc(1024, 16, GPU_MEMORY_DEFAULT, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, ptr != nullptr);

	gpuFree(ptr);

	gpuDeinit();
}

void checkGpuMallocAndFreeGpuMemory(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);

	void* ptr = gpuMalloc(1024, 16, GPU_MEMORY_GPU, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, ptr != nullptr);

	gpuFree(ptr);

	gpuDeinit();
}

void checkGpuHostToDevicePointerOnGpuMemory(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);

	void* ptr = gpuMalloc(256, 16, GPU_MEMORY_GPU, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, ptr != nullptr);

	void* devicePtr = gpuHostToDevicePointer(ptr, &result);

	TEST_ASSERT(test, result == GPU_ALLOCATION_MEMORY_IS_GPU);
	TEST_ASSERT(test, devicePtr == nullptr);

	gpuFree(ptr);

	gpuDeinit();
}

void checkGpuFreeInvalidPointer(Test* test) {
	(void)test;

	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);

	int dummy;
	gpuFree(&dummy); // Should not crash

	gpuDeinit();
}

void checkGpuHostToDevicePointer(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);

	void* ptr = gpuMalloc(256, 16, GPU_MEMORY_DEFAULT, &result);
	if (ptr == nullptr) {
		return;
	}

	void* devicePtr = gpuHostToDevicePointer(ptr, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, devicePtr != nullptr);

	gpuFree(ptr);

	gpuDeinit();
}

void checkGpuHostToDevicePointerWithOffset(Test* test) {
	GpuInitDesc desc = {};
	desc.backend = selectBackendForCurrentPlatform();
	desc.validationEnabled = true;

	GpuResult result;
	gpuInit(&desc, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuDeviceInfo* devices = nullptr;
	size_t count = 0;
	gpuEnumerateDevices(&devices, &count, &result);
	if (count == 0) {
		return;
	}

	gpuSelectDevice(devices[0].identifier, &result);

	void* ptr = gpuMalloc(256, 16, GPU_MEMORY_DEFAULT, &result);
	if (ptr == nullptr) {
		return;
	}

	void* baseDevicePtr = gpuHostToDevicePointer(ptr, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, baseDevicePtr != nullptr);

	ptr = (void*)((uintptr_t)ptr + 128);
	void* devicePtrWithOffset = gpuHostToDevicePointer(ptr, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, baseDevicePtr != nullptr);

	uintptr_t offset = (uintptr_t)devicePtrWithOffset - (uintptr_t)baseDevicePtr;
	TEST_ASSERT(test, offset = 128);

	gpuFree(ptr);

	gpuDeinit();
}

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

void checkGpuCreateComputePipeline(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	uint8_t* ir = nullptr;
	size_t irSize = 0;
	TEST_ASSERT(test, loadBinaryFile("build/compute.metallib", &ir, &irSize));

	GpuPipeline pipeline = gpuCreateComputePipeline(ir, irSize, nullptr, 0, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, pipeline != 0);

	freeBinaryFile(ir);

	gpuFreePipeline(pipeline);
	gpuDeinit();
}

void checkGpuCreateComputePipelineWithConstants(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	uint8_t* ir = nullptr;
	size_t irSize = 0;
	TEST_ASSERT(test, loadBinaryFile("build/compute_constants.metallib", &ir, &irSize));

	GpuFunctionConstants constants = {};
	constants.scale = 2.0f;

	GpuPipeline pipeline = gpuCreateComputePipeline(ir, irSize, &constants, sizeof(constants), &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, pipeline != 0);

	freeBinaryFile(ir);

	gpuFreePipeline(pipeline);
	gpuDeinit();
}

void checkGpuCreateComputePipelineInvalidIr(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	const uint8_t ir[] = { 0x13, 0x37, 0x00, 0x42 };
	GpuPipeline pipeline = gpuCreateComputePipeline(ir, sizeof(ir), nullptr, 0, &result);

	TEST_ASSERT(test, result == GPU_PIPELINE_IR_VALIDATION_FAILED);
	TEST_ASSERT(test, pipeline == 0);

	gpuDeinit();
}

void checkGpuCreateRenderPipeline(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	uint8_t* vertexIr = nullptr;
	size_t vertexIrSize = 0;
	TEST_ASSERT(test, loadBinaryFile("build/render_vertex.metallib", &vertexIr, &vertexIrSize));

	uint8_t* fragmentIr = nullptr;
	size_t fragmentIrSize = 0;
	TEST_ASSERT(test, loadBinaryFile("build/render_fragment.metallib", &fragmentIr, &fragmentIrSize));

	GpuPipeline pipeline = gpuCreateRenderPipeline(vertexIr, vertexIrSize, fragmentIr, fragmentIrSize, nullptr, 0, nullptr, 0, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, pipeline != 0);

	freeBinaryFile(vertexIr);
	freeBinaryFile(fragmentIr);

	gpuFreePipeline(pipeline);
	gpuDeinit();
}

void checkGpuCreateRenderPipelineWithConstants(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	uint8_t* vertexIr = nullptr;
	size_t vertexIrSize = 0;
	TEST_ASSERT(test, loadBinaryFile("build/render_vertex_constants.metallib", &vertexIr, &vertexIrSize));

	uint8_t* fragmentIr = nullptr;
	size_t fragmentIrSize = 0;
	TEST_ASSERT(test, loadBinaryFile("build/render_fragment_constants.metallib", &fragmentIr, &fragmentIrSize));

	GpuFunctionConstants vertexConstants = {};
	vertexConstants.scale = 3.0f;
	GpuFunctionConstants fragmentConstants = {};
	fragmentConstants.scale = 0.25f;

	GpuPipeline pipeline = gpuCreateRenderPipeline(vertexIr, vertexIrSize, fragmentIr, fragmentIrSize, &vertexConstants, sizeof(vertexConstants), &fragmentConstants, sizeof(fragmentConstants), &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, pipeline != 0);

	freeBinaryFile(vertexIr);
	freeBinaryFile(fragmentIr);

	gpuFreePipeline(pipeline);
	gpuDeinit();
}

void checkGpuCreateMeshletPipeline(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	uint8_t* meshletIr = nullptr;
	size_t meshletIrSize = 0;
	TEST_ASSERT(test, loadBinaryFile("build/meshlet.metallib", &meshletIr, &meshletIrSize));

	uint8_t* fragmentIr = nullptr;
	size_t fragmentIrSize = 0;
	TEST_ASSERT(test, loadBinaryFile("build/render_fragment.metallib", &fragmentIr, &fragmentIrSize));

	GpuPipeline pipeline = gpuCreateMeshletPipeline(meshletIr, meshletIrSize, fragmentIr, fragmentIrSize, nullptr, 0, nullptr, 0, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, pipeline != 0);

	freeBinaryFile(meshletIr);
	freeBinaryFile(fragmentIr);

	gpuFreePipeline(pipeline);
	gpuDeinit();
}

void checkGpuCreateMeshletPipelineWithConstants(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	uint8_t* meshletIr = nullptr;
	size_t meshletIrSize = 0;
	TEST_ASSERT(test, loadBinaryFile("build/meshlet_constants.metallib", &meshletIr, &meshletIrSize));

	uint8_t* fragmentIr = nullptr;
	size_t fragmentIrSize = 0;
	TEST_ASSERT(test, loadBinaryFile("build/render_fragment_constants.metallib", &fragmentIr, &fragmentIrSize));

	GpuFunctionConstants meshletConstants = {};
	meshletConstants.scale = 1.0f;
	GpuFunctionConstants fragmentConstants = {};
	fragmentConstants.scale = 0.5f;

	GpuPipeline pipeline = gpuCreateMeshletPipeline(meshletIr, meshletIrSize, fragmentIr, fragmentIrSize, &meshletConstants, sizeof(meshletConstants), &fragmentConstants, sizeof(fragmentConstants), &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, pipeline != 0);

	freeBinaryFile(meshletIr);
	freeBinaryFile(fragmentIr);

	gpuFreePipeline(pipeline);
	gpuDeinit();
}

void checkGpuAllocationCreatedAndDestroyedOnDifferentThreads(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	GpuAllocationCreatorContext creatorContext = {};
	creatorContext.bytes = 4096;
	creatorContext.align = 16;
	creatorContext.memory = GPU_MEMORY_DEFAULT;

	GpuAllocationDestroyerContext destroyerContext = {};
	destroyerContext.creator = &creatorContext;

	pthread_t creatorThread;
	int createResult = pthread_create(&creatorThread, nullptr, gpuAllocationCreatorThreadProc, &creatorContext);
	TEST_ASSERT(test, createResult == 0);

	pthread_t destroyerThread;
	createResult = pthread_create(&destroyerThread, nullptr, gpuAllocationDestroyerThreadProc, &destroyerContext);
	TEST_ASSERT(test, createResult == 0);

	int joinResult = pthread_join(creatorThread, nullptr);
	TEST_ASSERT(test, joinResult == 0);

	joinResult = pthread_join(destroyerThread, nullptr);
	TEST_ASSERT(test, joinResult == 0);

	TEST_ASSERT(test, creatorContext.createResult == GPU_SUCCESS);
	TEST_ASSERT(test, creatorContext.ptr != nullptr);
	TEST_ASSERT(test, cmnAtomicLoad(&destroyerContext.destroyed, CMN_ACQUIRE) == 1u);

	gpuDeinit();
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

void gpuTestSignalWritingOnGpuPtr(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
	}

	void* signalMemory = gpuMalloc(sizeof(uint64_t), 0, GPU_MEMORY_DEFAULT, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	void* gpuSignalMemory = gpuHostToDevicePointer(signalMemory, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	*(uint64_t*)signalMemory = 0;

	GpuQueue queue = gpuCreateQueue(&result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuSemaphore semaphore = gpuCreateSemaphore(0, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	GpuCommandBuffer commandBuffer = gpuStartCommandEncoding(queue, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuMemCpy(commandBuffer, gpuSignalMemory, gpuSignalMemory, sizeof(uint64_t), &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuSignalAfter(commandBuffer, GPU_STAGE_TRANSFER, gpuSignalMemory, 1, GPU_SIGNAL_ATOMIC_MAX, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuWaitBefore(commandBuffer, GPU_STAGE_TRANSFER, gpuSignalMemory, 1, GPU_OP_GREATER_EQUAL, GPU_HAZARD_NONE, -1, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuSubmitWithSignal(queue, &commandBuffer, 1, semaphore, 1, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	gpuWaitSemaphore(semaphore, 1, &result);
	TEST_ASSERT(test, result == GPU_SUCCESS);

	TEST_ASSERT(test, *(uint64_t*)signalMemory == 1);
}

