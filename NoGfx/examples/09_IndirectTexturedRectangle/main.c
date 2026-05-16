#include <stdio.h>
#include <unistd.h>
#include <gpu/gpu.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define OUTPUT_WIDTH 640
#define OUTPUT_HEIGHT 480

typedef float Position[3];
typedef float Color[2];
typedef struct VertexData {
	void* positions;
	void* uvs;
} Arguments;

const Position POSITIONS[] = {
	{ -0.5, -0.5, 0.0 },
	{  0.5, -0.5, 0.0 },
	{  0.5,  0.5, 0.0 },
	{ -0.5,  0.5, 0.0 },
};

const Color UVS[] = {
	{ 0.0, 1.0 },
	{ 1.0, 1.0 },
	{ 1.0, 0.0 },
	{ 0.0, 0.0 },
};

const uint32_t INDICES[] = {
	0, 1, 2,
	0, 2, 3,
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

typedef struct GpuAllocation {
	uint8_t*	cpu;
	uint8_t*	gpu;
} GpuAllocation;

typedef struct GpuBumpAllocator {
	uint8_t*	cpu;
	uint8_t*	gpu;
	uint32_t	size;
	uint32_t	offset;
} GpuBumpAllocator;

void createGpuBumpAllocator(GpuBumpAllocator* allocator, size_t size, GpuMemory memory) {
	allocator->cpu = (uint8_t*)gpuMalloc(size, 16, memory, NULL);
	allocator->gpu = (uint8_t*)gpuHostToDevicePointer(allocator->cpu, NULL);
	allocator->offset = 0;
	allocator->size = size;
}

GpuAllocation gpuBumpAlloc(GpuBumpAllocator* allocator, size_t bytes) {
	if (allocator->offset + bytes >= allocator->size) {
		allocator->offset = 0;
	}

	GpuAllocation alloc;
	alloc.cpu = allocator->cpu + allocator->offset;
	alloc.gpu = allocator->gpu + allocator->offset;

	allocator->offset += bytes;

	return alloc;
}

typedef struct GpuArena {
	uint8_t*	cpu;
	uint8_t*	gpu;
	size_t		size;
	size_t		offset;
} GpuArena;

void createGpuArena(GpuArena* arena, size_t size, GpuMemory memory) {
	if (memory == GPU_MEMORY_GPU) {
		arena->cpu = 0;
		arena->gpu = (uint8_t*)gpuMalloc(size, 16, GPU_MEMORY_GPU, NULL);
	} else {
		arena->cpu = (uint8_t*)gpuMalloc(size, 16, memory, NULL);
		arena->gpu = (uint8_t*)gpuHostToDevicePointer(arena->cpu, NULL);
	}

	arena->size = size;
	arena->offset = 0;
}

GpuAllocation gpuArenaAlloc(GpuArena* arena, size_t size) {
	if (arena->offset + size > arena->size) {
		return (GpuAllocation){};
	}

	size_t oldOffset = arena->offset;
	arena->offset += size;

	return (GpuAllocation){
		arena->cpu ? arena->cpu + oldOffset : NULL,
		arena->gpu + oldOffset
	};
}

GpuAllocation gpuArenaAllocAligned(GpuArena* arena, size_t size, size_t align) {
	if (align == 0) {
		align = 1;
	}

	size_t mask = align - 1;
	size_t alignedOffset = (arena->offset + mask) & ~mask;

	if (alignedOffset + size > arena->size) {
		return (GpuAllocation){};
	}

	arena->offset = alignedOffset + size;

	return (GpuAllocation){
		arena->cpu ? arena->cpu + alignedOffset : NULL,
		arena->gpu + alignedOffset
	};
}

typedef struct GpuContext {
	GpuQueue		queue;

	GpuSemaphore		onQueueDone;
	size_t			onQueueDoneNext;

	GpuBumpAllocator	bump;
	GpuArena		cpuArena;
	GpuArena		gpuArena;

	GpuAllocation		positions;
	GpuAllocation		uvs;
	GpuAllocation		indices;

	GpuAllocation		textureMemory;
	GpuTexture		texture;

	GpuAllocation		framebufferMemory;
	GpuTexture		framebuffer;

	GpuAllocation		readback;

	GpuPipeline		pipeline;
} GpuContext;
GpuContext gGpuContext;

GpuBackend selectBackend(void) {
	#ifdef __APPLE__
		return GPU_METAL_4;
	#else
		return GPU_VULKAN;
	#endif
}

void init(void) {
	GpuInitDesc desc;
	desc.backend		= selectBackend();
	desc.validationEnabled	= true;
	desc.tracingEnabled	= true;
	desc.extraLayers	= NULL;
	desc.extraLayerCount	= 0;

	GpuResult result = GPU_SUCCESS;

	gpuInit(&desc, &result);
	if (result != GPU_SUCCESS) {
		printf("Failed to initalize NoGfx. Got error %d.\n", result);
		exit(-1);
	}

	GpuDeviceInfo* devices;
	size_t devices_count;
	gpuEnumerateDevices(&devices, &devices_count, &result);
	if (result != GPU_SUCCESS) {
		printf("Failed to get the available devices. Got error %d.\n", result);
		exit(-1);
	}

	printf("Available devices:\n");
	for (size_t i = 0; i < devices_count; i++) {
		GpuDeviceInfo* info = &devices[i];

		printf(
			"\t%u - %s (%s - %s)\n",
			(unsigned int)info->identifier,
			info->name,
			info->vendor,
			info->type == GPU_INTEGRATED ? "Integrated" : "Dedicated"
		);
	}

	if (devices_count <= 0) {
		printf("No available devices found. Aborting.\n");
		exit(-1);
	}

	gpuSelectDevice(devices[0].identifier, &result);
	if (result != GPU_SUCCESS) {
		printf("Could not select a the specified device. Aborting.\n");
		exit(-1);
	}
	printf("Using device `%s`.\n", devices[0].name);

	gGpuContext.onQueueDone = gpuCreateSemaphore(0, &result);
	if (result != GPU_SUCCESS) {
		printf("Could not create a semaphore. Aborting.\n");
		exit(-1);
	}

	gGpuContext.queue = gpuCreateQueue(&result);
	if (result != GPU_SUCCESS) {
		printf("Could not create a queue. Aborting.\n");
		exit(-1);
	}

	createGpuBumpAllocator(&gGpuContext.bump, 16 * 1024 * 1024, GPU_MEMORY_DEFAULT);
	createGpuArena(&gGpuContext.gpuArena, 16 * 1024 * 1024, GPU_MEMORY_GPU);
	createGpuArena(&gGpuContext.cpuArena, 16 * 1024 * 1024, GPU_MEMORY_DEFAULT);
}

void initBuffers(void) {
	gGpuContext.positions	= gpuArenaAlloc(&gGpuContext.cpuArena, sizeof(POSITIONS));
	gGpuContext.uvs		= gpuArenaAlloc(&gGpuContext.cpuArena, sizeof(UVS));
	gGpuContext.indices	= gpuArenaAlloc(&gGpuContext.cpuArena, sizeof(INDICES));

	memcpy(gGpuContext.positions.cpu, POSITIONS, sizeof(POSITIONS));
	memcpy(gGpuContext.uvs.cpu, UVS, sizeof(UVS));
	memcpy(gGpuContext.indices.cpu, INDICES, sizeof(INDICES));

	gGpuContext.readback.cpu = (uint8_t*)gpuMalloc(OUTPUT_WIDTH * OUTPUT_HEIGHT * 4, 16, GPU_MEMORY_READBACK, NULL);
	gGpuContext.readback.gpu = (uint8_t*)gpuHostToDevicePointer(gGpuContext.readback.cpu, NULL);
}

void initFramebuffer(void) {
	GpuTextureDesc textureDescriptor = {};
	textureDescriptor.type = GPU_TEXTURE_2D;
	textureDescriptor.format = GPU_FORMAT_RGBA8_UNORM;
	textureDescriptor.usage = GPU_USAGE_COLOR_ATTACHMENT;
	textureDescriptor.dimensions[0] = OUTPUT_WIDTH;
	textureDescriptor.dimensions[1] = OUTPUT_HEIGHT;
	textureDescriptor.dimensions[2] = 1;
	textureDescriptor.layerCount = 1;
	textureDescriptor.mipCount = 1;
	textureDescriptor.sampleCount = 1;

	GpuTextureSizeAlign sizeAlign = gpuTextureSizeAlign(&textureDescriptor, NULL);

	gGpuContext.framebufferMemory = gpuArenaAllocAligned(&gGpuContext.gpuArena, sizeAlign.size, sizeAlign.align);
	gGpuContext.framebuffer = gpuCreateTexture(&textureDescriptor, gGpuContext.framebufferMemory.gpu, NULL);
}

void initPipeline(void) {
	size_t vertexIrSize;
	uint8_t* vertexIr = readEntireFile("vertex.metallib", &vertexIrSize);

	size_t fragmentIrSize;
	uint8_t* fragmentIr = readEntireFile("fragment.metallib", &fragmentIrSize);

	GpuColorTarget colorTarget = {};
	colorTarget.format = GPU_FORMAT_RGBA8_UNORM;
	colorTarget.writeMask = 0xFF;

	GpuRasterDesc raster = {};
	raster.topology = GPU_TOPOLOGY_TRIANGLE_LIST;
	raster.cull = GPU_CULL_NONE;
	raster.sampleCount = 1;
	raster.colorTargetCount = 1;
	raster.colorTargets = &colorTarget;

	gGpuContext.pipeline = gpuCreateRenderPipeline(
		vertexIr, vertexIrSize,
		fragmentIr, fragmentIrSize,
		NULL, 0,
		NULL, 0,
		&raster,
		NULL
	);
}

GpuTexture loadTexture(GpuCommandBuffer cb, const char* file, GpuAllocation* textureMemory) {
	FILE* handle = fopen(file, "rb");

	int x, y, channels;
	uint8_t* data = stbi_load_from_file(handle, &x, &y, &channels, 4);
	assert(channels == 4);

	GpuAllocation upload = gpuBumpAlloc(&gGpuContext.bump, x * y * 4);
	memcpy(upload.cpu, data, x * y * 4);
	STBI_FREE(data);

	GpuTextureDesc textureDescriptor = {};
	textureDescriptor.type = GPU_TEXTURE_2D;
	textureDescriptor.format = GPU_FORMAT_RGBA8_UNORM;
	textureDescriptor.usage = GPU_USAGE_SAMPLED;
	textureDescriptor.dimensions[0] = x;
	textureDescriptor.dimensions[1] = y;
	textureDescriptor.dimensions[2] = 1;
	textureDescriptor.layerCount = 1;
	textureDescriptor.mipCount = 1;
	textureDescriptor.sampleCount = 1;

	GpuTextureSizeAlign sizeNAlign = gpuTextureSizeAlign(&textureDescriptor, NULL);
	*textureMemory = gpuArenaAllocAligned(&gGpuContext.gpuArena, sizeNAlign.size, sizeNAlign.align);

	GpuTexture texture = gpuCreateTexture(&textureDescriptor, textureMemory->gpu, NULL);
	gpuCopyToTexture(cb, textureMemory->gpu, upload.gpu, texture, NULL);

	return texture;
}

void beginMainRenderpassOnFramebuffer(GpuCommandBuffer cb) {
	GpuRenderTarget frameBufferTarget = {};
	frameBufferTarget.texture = gGpuContext.framebuffer;
	frameBufferTarget.loadOp = GPU_OP_CLEAR;
	frameBufferTarget.storeOp = GPU_OP_STORE;
	frameBufferTarget.clearColor[0] = 0.0;
	frameBufferTarget.clearColor[1] = 0.0;
	frameBufferTarget.clearColor[2] = 0.0;
	frameBufferTarget.clearColor[3] = 1.0;

	GpuRenderPassDesc renderPass = {};
	renderPass.colorTargetCount = 1;
	renderPass.colorTargets = &frameBufferTarget;

	gpuBeginRenderPass(cb, &renderPass, NULL);
}

void draw(GpuCommandBuffer cb) {
	GpuViewDesc textureView = {};
	textureView.baseLayer = 0;
	textureView.baseMip = 0;
	textureView.layerCount = 1;
	textureView.mipCount = 1;
	textureView.format = GPU_FORMAT_RGBA8_UNORM;

	GpuAllocation textureHeapAlloc = gpuBumpAlloc(&gGpuContext.bump, sizeof(GpuTextureDescriptor));
	GpuTextureDescriptor* textureHeap = (GpuTextureDescriptor*)textureHeapAlloc.cpu;
	textureHeap[0] = gpuTextureViewDescriptor(gGpuContext.texture, &textureView, NULL);

	GpuAllocation argsAlloc = gpuBumpAlloc(&gGpuContext.bump, sizeof(Arguments));
	Arguments* args = (Arguments*)argsAlloc.cpu;
	args->positions = gGpuContext.positions.gpu;
	args->uvs = gGpuContext.uvs.gpu;

	GpuAllocation indirectArgsAlloc = gpuBumpAlloc(&gGpuContext.bump, sizeof(Arguments));
	GpuIndirectDrawArgs* indirectArgs = (GpuIndirectDrawArgs*)indirectArgsAlloc.cpu;
	indirectArgs->indexCount = 6;
	indirectArgs->instanceCount = 1;

	gpuSetActiveTextureHeapPtr(cb, textureHeapAlloc.gpu, NULL);
	gpuSetPipeline(cb, gGpuContext.pipeline, NULL);
	gpuDrawIndexedInstancedIndirect(cb, argsAlloc.gpu, NULL, gGpuContext.indices.gpu, indirectArgsAlloc.gpu, NULL);
}

int main(void) {
	init();
	initBuffers();
	initFramebuffer();
	initPipeline();

	GpuCommandBuffer cb = gpuStartCommandEncoding(gGpuContext.queue, NULL);

	gGpuContext.texture = loadTexture(cb, "./image.png", &gGpuContext.textureMemory);
	gpuBarrier(cb, GPU_STAGE_TRANSFER, GPU_STAGE_PIXEL_SHADER, GPU_HAZARD_NONE, NULL);

	beginMainRenderpassOnFramebuffer(cb);
		draw(cb);
	gpuEndRenderPass(cb, NULL);

	gpuBarrier(cb, GPU_STAGE_RASTER_COLOR_OUT, GPU_STAGE_TRANSFER, GPU_HAZARD_NONE, NULL);
	gpuCopyFromTexture(cb, gGpuContext.readback.gpu, gGpuContext.framebufferMemory.gpu, gGpuContext.framebuffer, NULL);
	gpuSubmitWithSignal(gGpuContext.queue, &cb, 1, gGpuContext.onQueueDone, 1, NULL);

	gpuWaitSemaphore(gGpuContext.onQueueDone, 1, NULL);

	stbi_write_png("out.png", OUTPUT_WIDTH, OUTPUT_HEIGHT, 4, gGpuContext.readback.cpu, OUTPUT_WIDTH * 4);
	
	gpuDeinit();
	return 0;
}

