#include "renderer.h"
#include "main.h"

#ifdef NOGFX_RENDERER

#include <gpu/gpu.h>

typedef float Vertex[2];

typedef float GpuBoid[4];

const Vertex BOID_VERTICES[] = {
	{ -5, -5 },
	{  5, -5 },
	{  0,  5 }
};

const uint32_t BOID_INDICES[] = {
	0,1, 2
};

uint8_t* readEntireFile(const char* file, size_t* fileLength) {
	FILE* handle = fopen(file, "rb");
	if (handle == NULL) {
		return NULL;
	}

	fseek(handle, 0L, SEEK_END);
	*fileLength = ftell(handle);
	fseek(handle, 0L, SEEK_SET);	

	uint8_t* buffer = (uint8_t*)calloc(1, *fileLength);
	if (buffer == NULL) {
		return NULL;
	}

	fread(buffer, sizeof(uint8_t), *fileLength, handle);
	fclose(handle);

	return buffer;
}


typedef struct {
	uint8_t*	cpu;
	uint8_t*	gpu;
} GpuAllocation;

typedef struct {
	uint8_t*	boids;
	uint8_t*	vertices;
} GpuArgs;

struct {
	NSView*			view;
	GpuSurface		surface;

	GpuAllocation		heap;
	GpuAllocation		boids[3];
	GpuAllocation		vertices;
	GpuAllocation		indices;
	GpuAllocation		args[3];

	GpuPipeline		renderPSO;

	GpuQueue		queue;

	GpuSemaphore		presentEvent;
	long			frameCount;

	FrameTimer		previousFrameWaitTimer;
	FrameTimer		uploadTimer;
	FrameTimer		drawTimer;
} gRenderer;

GpuResult gResult;
#define CHECK_RES() assert(gResult == GPU_SUCCESS);

void initRenderer(void) {

	GpuInitDesc initDesc = {
		GPU_METAL_4,
		false,
		false,
		NULL,
		0
	};
	gpuInit(&initDesc, &gResult);
	CHECK_RES();

	GpuDeviceInfo* deviceInfos;
	size_t devicesCount;
	gpuEnumerateDevices(&deviceInfos, &devicesCount, &gResult);
	CHECK_RES(); assert(devicesCount > 0);

	gpuSelectDevice(deviceInfos[0].identifier, &gResult);
	CHECK_RES();


	GpuFormat surfaceFormat = deviceInfos[0].capabilities.supportedSurfaceFormats[0];
	GpuSurfaceDesc surfaceDesc;
	surfaceDesc.type = GPU_SURFACE_VSYNC;
	// surfaceDesc.type = GPU_SURFACE_IMMEDIATE;
	surfaceDesc.format = surfaceFormat;
	surfaceDesc.framesInFlight = 3;
	surfaceDesc.size[0] = WINDOW_WIDTH;
	surfaceDesc.size[1] = WINDOW_HEIGHT;
	surfaceDesc.target.type = GPU_SURFACE_COCOA;
	surfaceDesc.target.cocoa.nsView = RGFW_window_getView_OSX(gState.window);
	gRenderer.surface = gpuCreateSurface(&surfaceDesc, &gResult); CHECK_RES();


	gRenderer.heap.cpu = (uint8_t*)gpuMalloc(sizeof(GpuBoid) * BOID_PRESERVE * 4, 0, GPU_MEMORY_DEFAULT, &gResult); CHECK_RES();
	gRenderer.heap.gpu = (uint8_t*)gpuHostToDevicePointer(gRenderer.heap.cpu, &gResult); CHECK_RES();

	gRenderer.boids[0].cpu = gRenderer.heap.cpu + sizeof(GpuBoid) * BOID_PRESERVE * 0;
	gRenderer.boids[0].gpu = gRenderer.heap.gpu + sizeof(GpuBoid) * BOID_PRESERVE * 0;
	gRenderer.boids[1].cpu = gRenderer.heap.cpu + sizeof(GpuBoid) * BOID_PRESERVE * 1;
	gRenderer.boids[1].gpu = gRenderer.heap.gpu + sizeof(GpuBoid) * BOID_PRESERVE * 1;
	gRenderer.boids[2].cpu = gRenderer.heap.cpu + sizeof(GpuBoid) * BOID_PRESERVE * 2;
	gRenderer.boids[2].gpu = gRenderer.heap.gpu + sizeof(GpuBoid) * BOID_PRESERVE * 2;

	gRenderer.vertices.cpu = gRenderer.heap.cpu + sizeof(GpuBoid) * BOID_PRESERVE * 3;
	gRenderer.vertices.gpu = gRenderer.heap.gpu + sizeof(GpuBoid) * BOID_PRESERVE * 3;
	gRenderer.indices.cpu = gRenderer.heap.cpu + sizeof(GpuBoid) * BOID_PRESERVE * 3 + 64;
	gRenderer.indices.gpu = gRenderer.heap.gpu + sizeof(GpuBoid) * BOID_PRESERVE * 3 + 64;

	gRenderer.args[0].cpu = gRenderer.heap.cpu + sizeof(GpuBoid) * BOID_PRESERVE * 3 + 64 + 16;
	gRenderer.args[0].gpu = gRenderer.heap.gpu + sizeof(GpuBoid) * BOID_PRESERVE * 3 + 64 + 16;
	gRenderer.args[1].cpu = gRenderer.heap.cpu + sizeof(GpuBoid) * BOID_PRESERVE * 3 + 64 + 32;
	gRenderer.args[1].gpu = gRenderer.heap.gpu + sizeof(GpuBoid) * BOID_PRESERVE * 3 + 64 + 32;
	gRenderer.args[2].cpu = gRenderer.heap.cpu + sizeof(GpuBoid) * BOID_PRESERVE * 3 + 64 + 48;
	gRenderer.args[2].gpu = gRenderer.heap.gpu + sizeof(GpuBoid) * BOID_PRESERVE * 3 + 64 + 48;


	memcpy(gRenderer.vertices.cpu, &BOID_VERTICES[0], sizeof(Vertex) * 3);
	memcpy(gRenderer.indices.cpu, &BOID_INDICES[0], sizeof(uint32_t) * 3);


	size_t vertexIrSize, fragmentIrSize;
	uint8_t* vertexIr = readEntireFile("boids.vertex.metallib", &vertexIrSize);
	uint8_t* fragmentIr = readEntireFile("boids.fragment.metallib", &fragmentIrSize);

	GpuColorTarget surfaceColorTarget = {
		surfaceFormat,
		0xF,
	};
	GpuRasterDesc rasterDesc = {
		GPU_TOPOLOGY_TRIANGLE_LIST,
		GPU_CULL_NONE,
		false,
		false,
		1,
		GPU_FORMAT_NONE,
		GPU_FORMAT_NONE,
		&surfaceColorTarget,
		1,
		NULL
	};

	float constants[2] = { WINDOW_WIDTH, WINDOW_HEIGHT };
	gRenderer.renderPSO = gpuCreateRenderPipeline(
		vertexIr, vertexIrSize,
		fragmentIr, fragmentIrSize,
		&constants, sizeof(float) * 2,
		NULL, 0,
		&rasterDesc, &gResult
	); CHECK_RES();


	gRenderer.queue = gpuCreateQueue(&gResult); CHECK_RES();


	gRenderer.presentEvent = gpuCreateSemaphore(0, &gResult); CHECK_RES();

	frameTimerInit(&gRenderer.previousFrameWaitTimer, "previous frame wait");
	frameTimerInit(&gRenderer.uploadTimer, "boid data upload");
	frameTimerInit(&gRenderer.drawTimer, "boid draw");
}

void draw(void) {
	double previousFrameWaitStart = frameTimerNowSeconds();
	if (gRenderer.frameCount > 3) {
		gpuWaitSemaphore(gRenderer.presentEvent, gRenderer.frameCount, &gResult); CHECK_RES();
	}
	frameTimerRecord(&gRenderer.previousFrameWaitTimer, frameTimerNowSeconds() - previousFrameWaitStart);

	int frameId = gRenderer.frameCount % 3;


	GpuTexture drawable = gpuAcquireNextDrawable(gRenderer.surface, &gResult);


	GpuBoid* gpuBoids = (GpuBoid*)gRenderer.boids[frameId].cpu;
	double uploadStart = frameTimerNowSeconds();
	for (int i = 0; i < gState.boidCount; i++) {
		gpuBoids[i][0] = gState.boids[i].x;
		gpuBoids[i][1] = gState.boids[i].y;
		gpuBoids[i][2] = gState.boids[i].dx;
		gpuBoids[i][3] = gState.boids[i].dy;
	}
	frameTimerRecord(&gRenderer.uploadTimer, frameTimerNowSeconds() - uploadStart);


	double drawStart = frameTimerNowSeconds();
	GpuCommandBuffer commandBuffer = gpuStartCommandEncoding(gRenderer.queue, &gResult); CHECK_RES();

	GpuRenderTarget surfaceTarget = {};
	surfaceTarget.texture = drawable;
	surfaceTarget.loadOp = GPU_OP_CLEAR;
	surfaceTarget.storeOp = GPU_OP_STORE;
	surfaceTarget.clearColor[0] = 0.2;
	surfaceTarget.clearColor[1] = 0.1;
	surfaceTarget.clearColor[2] = 1.5;

	GpuRenderPassDesc renderPassDesc = {};
	renderPassDesc.colorTargets = &surfaceTarget;
	renderPassDesc.colorTargetCount = 1;

	gpuBeginRenderPass(commandBuffer, &renderPassDesc, &gResult); CHECK_RES();

	GpuArgs* args = (GpuArgs*)gRenderer.args[frameId].cpu;
	args->boids = gRenderer.boids[frameId].gpu;
	args->vertices = gRenderer.vertices.gpu;

	gpuSetPipeline(commandBuffer, gRenderer.renderPSO, &gResult); CHECK_RES();
	gpuDrawIndexedInstanced(commandBuffer, gRenderer.args[frameId].gpu, NULL, gRenderer.indices.gpu, 3, gState.boidCount, &gResult); CHECK_RES();
	gpuEndRenderPass(commandBuffer, &gResult); CHECK_RES();

	gpuSubmitWithSignal(gRenderer.queue, &commandBuffer, 1, gRenderer.presentEvent, ++gRenderer.frameCount, &gResult); CHECK_RES();
	gpuPresent(gRenderer.queue, gRenderer.surface, &gResult); CHECK_RES();

	frameTimerRecord(&gRenderer.drawTimer, frameTimerNowSeconds() - drawStart);

	frameTimerPrintAndReset(&gRenderer.previousFrameWaitTimer);
	frameTimerPrintAndReset(&gRenderer.uploadTimer);
	frameTimerPrintAndReset(&gRenderer.drawTimer);
}

#endif
