#include "renderer.h"
#include "main.h"

#ifdef METAL4_RENDERER

#include <Metal/Metal.h>
#include <QuartzCore/QuartzCore.h>

typedef float Vertex[2];

typedef float GpuBoid[4];

const Vertex BOID_VERTICES[] = {
	{ -5, -5 },
	{  5, -5 },
	{  0,  5 }
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


struct {
	NSView*			view;
	CAMetalLayer*		layer;

	id<MTLDevice>		device;
	id<MTL4Compiler>	compiler;
	id<MTL4CommandAllocator>	commandAllocator;

	id<MTL4ArgumentTable>	argumentTable;

	id<MTLResidencySet>	residencySet;
	id<MTLHeap>		heap;
	id<MTLBuffer>		boids[3];
	id<MTLBuffer>		vertices;

	id<MTLRenderPipelineState>	renderPSO;

	id<MTL4CommandQueue>	queue;

	id<MTLSharedEvent>	presentEvent;
	long			frameCount;
	FrameTimer		previousFrameWaitTimer;
	FrameTimer		uploadTimer;
	FrameTimer		drawTimer;
} gRenderer;

void initRenderer(void) { @autoreleasepool {
	gRenderer.device = MTLCreateSystemDefaultDevice();


	gRenderer.view = (NSView*)RGFW_window_getView_OSX(gState.window);

	gRenderer.layer = [CAMetalLayer new];
	gRenderer.layer.device = gRenderer.device;
	gRenderer.layer.frame = gRenderer.view.frame;
	gRenderer.layer.maximumDrawableCount = 3;
	gRenderer.layer.displaySyncEnabled = YES;
	gRenderer.view.wantsLayer = YES;
	gRenderer.view.layer = gRenderer.layer;


	MTLHeapDescriptor* heapDesc = [[MTLHeapDescriptor new] autorelease];
	heapDesc.size = sizeof(GpuBoid) * BOID_PRESERVE * 4;
	heapDesc.resourceOptions = MTLResourceStorageModeShared | MTLResourceHazardTrackingModeTracked;

	gRenderer.heap = [gRenderer.device newHeapWithDescriptor:heapDesc];

	gRenderer.boids[0] = [gRenderer.heap newBufferWithLength:sizeof(GpuBoid) * BOID_PRESERVE options:MTLResourceStorageModeShared | MTLResourceHazardTrackingModeTracked];
	gRenderer.boids[1] = [gRenderer.heap newBufferWithLength:sizeof(GpuBoid) * BOID_PRESERVE options:MTLResourceStorageModeShared | MTLResourceHazardTrackingModeTracked];
	gRenderer.boids[2] = [gRenderer.heap newBufferWithLength:sizeof(GpuBoid) * BOID_PRESERVE options:MTLResourceStorageModeShared | MTLResourceHazardTrackingModeTracked];

	gRenderer.vertices = [gRenderer.heap newBufferWithLength:sizeof(Vertex) * 3 options:MTLResourceStorageModeShared | MTLResourceHazardTrackingModeTracked];
	memcpy([gRenderer.vertices contents], &BOID_VERTICES[0], sizeof(Vertex) * 3);

	assert(gRenderer.boids[0] != NULL && gRenderer.boids[1] != NULL && gRenderer.boids[2] != NULL && gRenderer.vertices != NULL);


	gRenderer.commandAllocator = [gRenderer.device newCommandAllocator];


	MTL4CompilerDescriptor* compilerDesc = [[MTL4CompilerDescriptor new] autorelease];
	gRenderer.compiler = [gRenderer.device newCompilerWithDescriptor:compilerDesc error:nil];

	size_t irSize;
	uint8_t* ir = readEntireFile("boids.metallib", &irSize);

	dispatch_data_t data = dispatch_data_create(ir, irSize, dispatch_get_main_queue(), NULL);
	id<MTLLibrary> library = [gRenderer.device newLibraryWithData:data error:nil];

	MTL4LibraryFunctionDescriptor* vertexBaseFunction = [[MTL4LibraryFunctionDescriptor new] autorelease];
	vertexBaseFunction.name = @"vertexMain";
	vertexBaseFunction.library = library;
	
	float windowWidth = WINDOW_WIDTH, windowHeight = WINDOW_HEIGHT;
	MTLFunctionConstantValues* vertexConstants = [[MTLFunctionConstantValues new] autorelease];
	[vertexConstants setConstantValue:&windowWidth type:MTLDataTypeFloat atIndex:0];
	[vertexConstants setConstantValue:&windowHeight type:MTLDataTypeFloat atIndex:1];

	MTL4SpecializedFunctionDescriptor* vertexFunction = [[MTL4SpecializedFunctionDescriptor new] autorelease];
	vertexFunction.constantValues = vertexConstants;
	vertexFunction.functionDescriptor = vertexBaseFunction;

	MTL4LibraryFunctionDescriptor* fragmentFunction = [[MTL4LibraryFunctionDescriptor new] autorelease];
	fragmentFunction.name = @"fragmentMain";
	fragmentFunction.library = library;


	MTL4RenderPipelineDescriptor* pipelineDesc = [[MTL4RenderPipelineDescriptor new] autorelease];
	pipelineDesc.vertexFunctionDescriptor = vertexFunction;
	pipelineDesc.fragmentFunctionDescriptor = fragmentFunction;
	pipelineDesc.colorAttachments[0].pixelFormat = gRenderer.layer.pixelFormat;

	gRenderer.renderPSO = [gRenderer.compiler newRenderPipelineStateWithDescriptor:pipelineDesc compilerTaskOptions:nil error:nil];


	MTLResidencySetDescriptor* residencySetDesc = [[MTLResidencySetDescriptor new] autorelease];
	residencySetDesc.initialCapacity = 1;

	gRenderer.residencySet = [gRenderer.device newResidencySetWithDescriptor:residencySetDesc error:nil];
	[gRenderer.residencySet addAllocation:gRenderer.heap];
	[gRenderer.residencySet commit];


	MTL4ArgumentTableDescriptor* argumentTableDesc = [[MTL4ArgumentTableDescriptor new] autorelease];
	argumentTableDesc.maxBufferBindCount = 2;

	gRenderer.argumentTable = [gRenderer.device newArgumentTableWithDescriptor:argumentTableDesc error:nil];


	gRenderer.queue = [gRenderer.device newMTL4CommandQueue];
	[gRenderer.queue addResidencySet:gRenderer.residencySet];
	[gRenderer.queue addResidencySet:gRenderer.layer.residencySet];


	gRenderer.presentEvent = [gRenderer.device newSharedEvent];
	gRenderer.presentEvent.signaledValue = 0;

	frameTimerInit(&gRenderer.previousFrameWaitTimer, "previous frame wait");
	frameTimerInit(&gRenderer.uploadTimer, "boid data upload");
	frameTimerInit(&gRenderer.drawTimer, "boid draw");
}}

void draw(void) { @autoreleasepool {
	double previousFrameWaitStart = frameTimerNowSeconds();
	if (gRenderer.frameCount > 3) {
		[gRenderer.presentEvent waitUntilSignaledValue:gRenderer.frameCount timeoutMS:-1];
	}
	frameTimerRecord(&gRenderer.previousFrameWaitTimer, frameTimerNowSeconds() - previousFrameWaitStart);

	int frameId = gRenderer.frameCount % 3;

	id<CAMetalDrawable> drawable = [gRenderer.layer nextDrawable];

	id<MTL4CommandBuffer> commandBuffer = [[gRenderer.device newCommandBuffer] autorelease];
	[commandBuffer beginCommandBufferWithAllocator:gRenderer.commandAllocator];

	GpuBoid* gpuBoids = (GpuBoid*)[gRenderer.boids[frameId] contents];
	double uploadStart = frameTimerNowSeconds();
	for (int i = 0; i < gState.boidCount; i++) {
		gpuBoids[i][0] = gState.boids[i].x;
		gpuBoids[i][1] = gState.boids[i].y;
		gpuBoids[i][2] = gState.boids[i].dx;
		gpuBoids[i][3] = gState.boids[i].dy;
	}
	frameTimerRecord(&gRenderer.uploadTimer, frameTimerNowSeconds() - uploadStart);

	double drawStart = frameTimerNowSeconds();
	MTL4RenderPassDescriptor* renderPassDesc = [[MTL4RenderPassDescriptor new] autorelease];
	renderPassDesc.colorAttachments[0].texture = drawable.texture;
	renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.2, 0.1, 1.5, 0.0);
	renderPassDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
	renderPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

	id<MTL4RenderCommandEncoder> renderpass = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDesc];

	[gRenderer.argumentTable setAddress:[gRenderer.boids[frameId] gpuAddress] atIndex:0];
	[gRenderer.argumentTable setAddress:[gRenderer.vertices gpuAddress] atIndex:1];

	[renderpass setArgumentTable:gRenderer.argumentTable atStages:MTLRenderStageVertex];
	[renderpass setRenderPipelineState:gRenderer.renderPSO];
	[renderpass drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3 instanceCount:gState.boidCount];

	[renderpass endEncoding];

	[commandBuffer endCommandBuffer];

	[gRenderer.queue waitForDrawable:drawable];
	[gRenderer.queue commit:&commandBuffer count: 1];
	[gRenderer.queue signalDrawable:drawable];
	[gRenderer.queue signalEvent:gRenderer.presentEvent value:++gRenderer.frameCount];

	[drawable present];
	frameTimerRecord(&gRenderer.drawTimer, frameTimerNowSeconds() - drawStart);

	frameTimerPrintAndReset(&gRenderer.previousFrameWaitTimer);
	frameTimerPrintAndReset(&gRenderer.uploadTimer);
	frameTimerPrintAndReset(&gRenderer.drawTimer);
} }

#endif
