#include "gpu/gpu.h"
#include "gpu_common.h"

#include <pthread.h>
#include <sched.h>
#include <lib/common/atomic.h>

void createDummyRasterDesc(GpuRasterDesc* desc) {
	*desc = {};

	desc->topology = GPU_TOPOLOGY_TRIANGLE_LIST;
	desc->cull = GPU_CULL_ALL;
	desc->alphaToCoverage = false;
	desc->supportDualSourceBlending = false;
	desc->sampleCount = 1;
	desc->depthFormat = GPU_FORMAT_NONE;
	desc->stencilFormat = GPU_FORMAT_NONE;
	desc->colorTargets = nullptr;
	desc->colorTargetCount = 0;
	desc->blendstate = nullptr;
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

	uint32_t groupSize[3] = { 1, 1, 1 };
	GpuPipeline pipeline = gpuCreateComputePipeline(ir, irSize, nullptr, 0, groupSize, &result);

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

	uint32_t groupSize[3] = { 1, 1, 1 };
	GpuPipeline pipeline = gpuCreateComputePipeline(ir, irSize, &constants, sizeof(constants), groupSize, &result);

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
	uint32_t groupSize[3] = { 1, 1, 1 };
	GpuPipeline pipeline = gpuCreateComputePipeline(ir, sizeof(ir), nullptr, 0, groupSize, &result);

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

	GpuRasterDesc rasterDesc;
	createDummyRasterDesc(&rasterDesc);
	GpuPipeline pipeline = gpuCreateRenderPipeline(vertexIr, vertexIrSize, fragmentIr, fragmentIrSize, nullptr, 0, nullptr, 0, &rasterDesc, &result);

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

	GpuRasterDesc rasterDesc;
	createDummyRasterDesc(&rasterDesc);
	GpuPipeline pipeline = gpuCreateRenderPipeline(vertexIr, vertexIrSize, fragmentIr, fragmentIrSize, &vertexConstants, sizeof(vertexConstants), &fragmentConstants, sizeof(fragmentConstants), &rasterDesc, &result);

	TEST_ASSERT(test, result == GPU_SUCCESS);
	TEST_ASSERT(test, pipeline != 0);

	freeBinaryFile(vertexIr);
	freeBinaryFile(fragmentIr);

	gpuFreePipeline(pipeline);
	gpuDeinit();
}


typedef struct GpuPipelineStressThreadContext {
	GpuStressGate* gate;
	const uint8_t* computeIr;
	size_t computeIrSize;
	const uint8_t* vertexIr;
	size_t vertexIrSize;
	const uint8_t* fragmentIr;
	size_t fragmentIrSize;
	GpuFunctionConstants constants;
	size_t iterations;
	uint32_t completed;
	uint32_t failed;
} GpuPipelineStressThreadContext;

static void* gpuPipelineStressThreadProc(void* ptr) {
	GpuPipelineStressThreadContext* context = (GpuPipelineStressThreadContext*)ptr;

	gpuWaitForStressStart(context->gate);

	uint32_t groupSize[3] = { 1, 1, 1 };

	for (size_t i = 0; i < context->iterations; i++) {
		GpuResult pipelineResult = GPU_GENERAL_ERROR;
		GpuPipeline pipeline = 0;

		switch (i % 2u) {
			case 0u:
				pipeline = gpuCreateComputePipeline(context->computeIr, context->computeIrSize, &context->constants, sizeof(context->constants), groupSize, &pipelineResult);
				break;
			case 1u:
				GpuRasterDesc rasterDesc;
				createDummyRasterDesc(&rasterDesc);
				pipeline = gpuCreateRenderPipeline(
					context->vertexIr, context->vertexIrSize,
					context->fragmentIr, context->fragmentIrSize,
					&context->constants, sizeof(context->constants),
					&context->constants, sizeof(context->constants),
					&rasterDesc,
					&pipelineResult
				);
				break;
		}

		if (pipelineResult != GPU_SUCCESS || pipeline == 0) {
			context->failed = 1u;
			context->completed = 1u;
			return nullptr;
		}

		gpuFreePipeline(pipeline);
	}

	context->completed = 1u;
	return nullptr;
}

static void runGpuPipelineStress(Test* test) {
	GpuResult result;
	if (!initGpuAndSelectFirstDevice(&result)) {
		TEST_ASSERT(test, result == GPU_SUCCESS);
		return;
	}

	uint8_t* computeIr = nullptr;
	size_t computeIrSize = 0;
	TEST_ASSERT(test, loadBinaryFile("build/compute_constants.metallib", &computeIr, &computeIrSize));

	uint8_t* vertexIr = nullptr;
	size_t vertexIrSize = 0;
	TEST_ASSERT(test, loadBinaryFile("build/render_vertex_constants.metallib", &vertexIr, &vertexIrSize));

	uint8_t* fragmentIr = nullptr;
	size_t fragmentIrSize = 0;
	TEST_ASSERT(test, loadBinaryFile("build/render_fragment_constants.metallib", &fragmentIr, &fragmentIrSize));

	const size_t threadCount = 6;
	const size_t iterations = 96;

	GpuStressGate gate = {};
	GpuPipelineStressThreadContext contexts[threadCount] = {};
	pthread_t threads[threadCount];

	for (size_t i = 0; i < threadCount; i++) {
		contexts[i].gate = &gate;
		contexts[i].computeIr = computeIr;
		contexts[i].computeIrSize = computeIrSize;
		contexts[i].vertexIr = vertexIr;
		contexts[i].vertexIrSize = vertexIrSize;
		contexts[i].fragmentIr = fragmentIr;
		contexts[i].fragmentIrSize = fragmentIrSize;
		contexts[i].constants.scale = 1.5f;
		contexts[i].iterations = iterations;

		int createResult = pthread_create(&threads[i], nullptr, gpuPipelineStressThreadProc, &contexts[i]);
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

	freeBinaryFile(computeIr);
	freeBinaryFile(vertexIr);
	freeBinaryFile(fragmentIr);

	gpuDeinit();
}

void checkGpuConcurrentPipelineStress(Test* test) {
	runGpuPipelineStress(test);
}
