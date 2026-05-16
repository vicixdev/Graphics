#ifndef MTL4_COMMAND_H
#define MTL4_COMMAND_H

#include <gpu/gpu.h>
#include <lib/metal4/textures.h>
#include <lib/metal4/pipelines.h>
#include <lib/metal4/depthstencilstates.h>
#include <lib/metal4/blend_states.h>

typedef enum Mtl4CommandType {
	MTL4_CMD_COPY_BUFFER_TO_BUFFER = 0,
	MTL4_CMD_COPY_BUFFER_TO_TEXTURE,
	MTL4_CMD_COPY_TEXTURE_TO_BUFFER,

	MTL4_CMD_DISPATCH,
	MTL4_CMD_DISPATCH_INDIRECT,

	MTL4_CMD_SIGNAL,
	MTL4_CMD_WAIT,

	MTL4_CMD_BEGIN_RENDERPASS,
	MTL4_CMD_END_RENDERPASS,
	MTL4_CMD_DRAW,
	MTL4_CMD_DRAW_INDIRECT,
	MTL4_CMD_MULTIDRAW_INDIRECT,
} Mtl4CommandType;

typedef struct Mtl4CommandCopyBufferToBuffer {
	void*	destination;
	void*	source;
	size_t	size;
} Mtl4CommandCopyBufferToBuffer;

typedef struct Mtl4CommandCopyBufferToTexture {
	Mtl4Texture	destinationTexture;
	void*		destinationPtr;
	void*		source;
} Mtl4CommandCopyBufferToTexture;

typedef struct Mtl4CommandCopyTextureToBuffer {
	void*		destination;
	void*		sourcePtr;
	Mtl4Texture	sourceTexture;
} Mtl4CommandCopyTextureToBuffer;

typedef struct Mtl4CommandSignal {
	void*		signal;
	uint64_t	value;
} Mtl4CommandSignal;

typedef struct Mtl4CommandWait {
	void*		signal;
	uint64_t	value;
} Mtl4CommandWait;

typedef struct Mtl4CommandDispatch {
	Mtl4Pipeline	pipeline;

	void*		data;
	uint32_t	gridDimensions[3];
} Mtl4CommandDispatch;

typedef struct Mtl4CommandDispatchIndirect {
	Mtl4Pipeline	pipeline;

	void*		data;
	void*		indirectArgs;
} Mtl4CommandDispatchIndirect;

typedef struct Mtl4CommandBeginRenderPass {
	const GpuRenderPassDesc*	renderPass;
} Mtl4CommandBeginRenderPass;

typedef struct Mtl4CommandEndRenderPass {
} Mtl4CommandEndRenderPass;

typedef struct Mtl4CommandDraw {
	Mtl4Pipeline			pipeline;
	Mtl4DepthStencilState		depthStencil;
	Mtl4BlendState			blend;
	void*				textureHeapPtr;

	void*				vertexData;
	void*				pixelData;
	void*				indices;
	uint32_t			indexCount;
	uint32_t			instanceCount;
} Mtl4CommandDraw;

typedef struct Mtl4CommandDrawIndirect {
	Mtl4Pipeline			pipeline;
	Mtl4DepthStencilState		depthStencil;
	Mtl4BlendState			blend;
	void*				textureHeapPtr;

	void*				vertexData;
	void*				pixelData;
	void*				indices;
	void*				indirectArgs;
} Mtl4CommandDrawIndirect;

typedef struct Mtl4CommandMultiDrawIndirect {
} Mtl4CommandMultiDrawIndirect;

typedef struct Mtl4Command {
	Mtl4CommandType	type;

	// NOTE: Can be used only for compute or render pass begin.
	GpuStageFlags	waitFor;
	GpuHazardFlags	waitingHazards;

	union {
		Mtl4CommandCopyBufferToBuffer	copyBufferToBuffer;
		Mtl4CommandCopyBufferToTexture	copyBufferToTexture;
		Mtl4CommandCopyTextureToBuffer	copyTextureToBuffer;

		Mtl4CommandDispatch		dispatch;
		Mtl4CommandDispatchIndirect	dispatchIndirect;

		Mtl4CommandSignal		signal;
		Mtl4CommandWait			wait;

		Mtl4CommandBeginRenderPass	beginRenderPass;
		Mtl4CommandEndRenderPass	endRenderPass;
		Mtl4CommandDraw			draw;
		Mtl4CommandDrawIndirect		drawIndirect;
		Mtl4CommandMultiDrawIndirect	multiDrawIndirect;
	};
} Mtl4Command;

#endif // MTL4_COMMAND_H

