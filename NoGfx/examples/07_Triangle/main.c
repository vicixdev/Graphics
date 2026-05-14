#include <stdio.h>
#include <unistd.h>
#include <gpu/gpu.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define OUTPUT_WIDTH 640
#define OUTPUT_HEIGHT 480

typedef float Position[3];
typedef float Color[3];
typedef struct VertexData {
	void* positions;
	void* colors;
} VertexData;

const Position POSITIONS[] = {
	{ -0.5, -0.5, 0.0 },
	{  0.5, -0.5, 0.0 },
	{  0.0,  0.5, 0.0 },
};

const Color COLORS[] = {
	{ 1.0, 0.0, 0.0 },
	{ 0.0, 1.0, 0.0 },
	{ 0.0, 0.0, 1.0 },
};

const uint32_t INDICES[] = {
	0, 1, 2
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

GpuBackend selectBackend(void) {
	#ifdef __APPLE__
		return GPU_METAL_4;
	#else
		return GPU_VULKAN;
	#endif
}

int main(void) {
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
		return -1;
	}

	GpuDeviceInfo* devices;
	size_t devices_count;
	gpuEnumerateDevices(&devices, &devices_count, &result);
	if (result != GPU_SUCCESS) {
		printf("Failed to get the available devices. Got error %d.\n", result);
		return -1;
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
		return -1;
	}

	gpuSelectDevice(devices[0].identifier, &result);
	if (result != GPU_SUCCESS) {
		printf("Could not select a the specified device. Aborting.\n");
		return -1;
	}
	printf("Using device `%s`.\n", devices[0].name);

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

	GpuPipeline pipeline = gpuCreateRenderPipeline(
		vertexIr, vertexIrSize,
		fragmentIr, fragmentIrSize,
		NULL, 0,
		NULL, 0,
		&raster,
		NULL
	);

	GpuSemaphore semaphore = gpuCreateSemaphore(0, &result);
	if (result != GPU_SUCCESS) {
		printf("Could not create a semaphore. Aborting.\n");
		return -1;
	}

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

	void* gpuTextureBuffer = gpuMalloc(sizeAlign.size + 1024, sizeAlign.align, GPU_MEMORY_GPU, NULL);
	GpuTexture texture = gpuCreateTexture(&textureDescriptor, gpuTextureBuffer, &result);
	if (result != GPU_SUCCESS) {
		printf("Failed to create texture. Got error %d.\n", result);
		gpuDeinit();
		return -1;
	}

	uint8_t* downloadBuffer = (uint8_t*)gpuMalloc(OUTPUT_WIDTH * OUTPUT_HEIGHT * 4, 0, GPU_MEMORY_READBACK, NULL);
	void* deviceDownloadBuffer = gpuHostToDevicePointer(downloadBuffer, NULL);

	Position* positions = (Position*)gpuMalloc(sizeof(Position) * 3, 0, GPU_MEMORY_DEFAULT, NULL);
	Color* colors = (Color*)gpuMalloc(sizeof(Color) * 3, 0, GPU_MEMORY_DEFAULT, NULL);
	VertexData* vertexData = (VertexData*)gpuMalloc(sizeof(VertexData), 0, GPU_MEMORY_DEFAULT, NULL);
	uint32_t* indices = (uint32_t*)gpuMalloc(sizeof(uint32_t) * 3, 0, GPU_MEMORY_DEFAULT, NULL);

	void* devicePositions = gpuHostToDevicePointer(positions, NULL);
	void* deviceColors = gpuHostToDevicePointer(colors, NULL);
	void* deviceVertexData = gpuHostToDevicePointer(vertexData, NULL);
	void* deviceIndices = gpuHostToDevicePointer(indices, NULL);

	memcpy(positions, POSITIONS, sizeof(POSITIONS));
	memcpy(colors, COLORS, sizeof(COLORS));
	memcpy(indices, INDICES, sizeof(INDICES));
	vertexData->positions = devicePositions;
	vertexData->colors = deviceColors;

	GpuQueue queue = gpuCreateQueue(NULL);

	GpuRenderTarget renderTarget = {};
	renderTarget.texture = texture;
	renderTarget.clearColor[0] = 0.0f;
	renderTarget.clearColor[1] = 0.0f;
	renderTarget.clearColor[2] = 0.0f;
	renderTarget.clearColor[3] = 1.0f;
	renderTarget.loadOp = GPU_OP_CLEAR;
	renderTarget.storeOp = GPU_OP_STORE;

	GpuRenderPassDesc renderPass = {};
	renderPass.colorTargetCount = 1;
	renderPass.colorTargets = &renderTarget;

	GpuCommandBuffer commandBuffer = gpuStartCommandEncoding(queue, NULL);
	gpuBeginRenderPass(commandBuffer, &renderPass, NULL);
		gpuSetPipeline(commandBuffer, pipeline, NULL);
		gpuDrawIndexedInstanced(commandBuffer, deviceVertexData, NULL, deviceIndices, 3, 1, NULL);
	gpuEndRenderPass(commandBuffer, NULL);
	gpuSubmitWithSignal(queue, &commandBuffer, 1, semaphore, 1, NULL);

	gpuWaitSemaphore(semaphore, 1, NULL);

	commandBuffer = gpuStartCommandEncoding(queue, NULL);
	gpuCopyFromTexture(commandBuffer, deviceDownloadBuffer, gpuTextureBuffer, texture, NULL);
	gpuSubmitWithSignal(queue, &commandBuffer, 1, semaphore, 2, NULL);

	gpuWaitSemaphore(semaphore, 2, NULL);

	stbi_write_png("out.png", OUTPUT_WIDTH, OUTPUT_HEIGHT, 4, downloadBuffer, OUTPUT_WIDTH * 4);
	
	gpuDeinit();
	return 0;
}

