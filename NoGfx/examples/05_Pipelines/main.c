#include <stdio.h>
#include <stdlib.h>
#include <gpu/gpu.h>

GpuBackend selectBackend(void) {
	#ifdef __APPLE__
		return GPU_METAL_4;
	#else
		return GPU_VULKAN;
	#endif
}

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

#define ADD_VECTOR_LEN 1024
#define ADD_VECTOR_SIZE ADD_VECTOR_LEN * sizeof(uint32_t)

typedef struct Arguments {
	const void* left;
	const void* right;
	const void* result;
} Arguments;

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

	size_t addPipelineIrSize;
	uint8_t* addPipelineIr = readEntireFile("./kernel.metallib", &addPipelineIrSize);
	if (addPipelineIr == NULL) {
		printf("Could not read the pipeline ir from disk. Aborting.\n");
		return -1;
	}

	uint32_t groupSize[3] = { 1, 1, 1 };
	GpuPipeline pipeline = gpuCreateComputePipeline(addPipelineIr, addPipelineIrSize, NULL, 0, groupSize, NULL);

	uint32_t* leftBuffer = (uint32_t*)gpuMalloc(ADD_VECTOR_SIZE, 0, GPU_MEMORY_DEFAULT, NULL);
	uint32_t* rightBuffer = (uint32_t*)gpuMalloc(ADD_VECTOR_SIZE, 0, GPU_MEMORY_DEFAULT, NULL);
	uint32_t* resultBuffer = (uint32_t*)gpuMalloc(ADD_VECTOR_SIZE, 0, GPU_MEMORY_READBACK, NULL);
	Arguments* argumentBuffer = (Arguments*)gpuMalloc(sizeof(Arguments), 0, GPU_MEMORY_DEFAULT, NULL);
	uint32_t* indirectBuffer = (uint32_t*)gpuMalloc(sizeof(uint32_t[3]), 0, GPU_MEMORY_DEFAULT, NULL);

	void* deviceLeftBuffer = gpuHostToDevicePointer(leftBuffer, NULL);
	void* deviceRightBuffer = gpuHostToDevicePointer(rightBuffer, NULL);
	void* deviceResultBuffer = gpuHostToDevicePointer(resultBuffer, NULL);
	void* deviceArgumentBuffer = gpuHostToDevicePointer(argumentBuffer, NULL);
	void* deviceIndirectBuffer = gpuHostToDevicePointer(indirectBuffer, NULL);

	GpuQueue queue = gpuCreateQueue(NULL);
	GpuSemaphore semaphore = gpuCreateSemaphore(0, NULL);

	{
		printf("Performing [0,1024) + [1024, 2048) via a direct dispatch...\n");

		for (size_t i = 0; i < ADD_VECTOR_LEN; i++) {
			leftBuffer[i] = i;
			rightBuffer[i] = ADD_VECTOR_LEN + i;
		}

		argumentBuffer->left = deviceLeftBuffer;
		argumentBuffer->right = deviceRightBuffer;
		argumentBuffer->result = deviceResultBuffer;

		GpuCommandBuffer commandBuffer = gpuStartCommandEncoding(queue, NULL);
		gpuSetPipeline(commandBuffer, pipeline, NULL);
		gpuDispatch(commandBuffer, deviceArgumentBuffer, (uint32_t[3]){ ADD_VECTOR_LEN, 1, 1}, NULL);

		gpuSubmitWithSignal(queue, &commandBuffer, 1, semaphore, 1, NULL);
		gpuWaitSemaphore(semaphore, 1, NULL);

		printf("Direct Result: [ ");
		for (size_t i = 0; i < ADD_VECTOR_LEN; i++) {
			printf("%d ", resultBuffer[i]);
		}
		printf("]\n");
	}

	{
		printf("Performing [2048, 3072) + [1024, 2048) via an indirect dispatch...\n");

		for (size_t i = 0; i < ADD_VECTOR_LEN; i++) {
			leftBuffer[i] = ADD_VECTOR_LEN * 2 + i;
			rightBuffer[i] = ADD_VECTOR_LEN + i;
		}

		argumentBuffer->left = deviceLeftBuffer;
		argumentBuffer->right = deviceRightBuffer;
		argumentBuffer->result = deviceResultBuffer;

		indirectBuffer[0] = ADD_VECTOR_LEN;
		indirectBuffer[1] = 1;
		indirectBuffer[2] = 1;

		GpuCommandBuffer commandBuffer = gpuStartCommandEncoding(queue, NULL);
		gpuSetPipeline(commandBuffer, pipeline, NULL);
		gpuDispatchIndirect(commandBuffer, deviceArgumentBuffer, deviceIndirectBuffer, NULL);

		gpuSubmitWithSignal(queue, &commandBuffer, 1, semaphore, 2, NULL);
		gpuWaitSemaphore(semaphore, 2, NULL);

		printf("Indirect Result: [ ");
		for (size_t i = 0; i < ADD_VECTOR_LEN; i++) {
			printf("%d ", resultBuffer[i]);
		}
		printf("]\n");
	}

	gpuDeinit();
	return 0;
}

