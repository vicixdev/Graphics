#ifndef MTL4_COMMAND_H
#define MTL4_COMMAND_H

#include <gpu/gpu.h>
#include <lib/common/chain.h>
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

	MTL4_CMD_RENDERPASS,
} Mtl4CommandType;

typedef enum Mtl4RenderCommandType {
	MTL4_CMD_DRAW,
	MTL4_CMD_DRAW_INDIRECT,
	MTL4_CMD_MULTIDRAW_INDIRECT,
} Mtl4RenderCommandType;

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

typedef struct Mtl4CommandDraw {
	void*				vertexData;
	void*				pixelData;
	void*				indices;
	uint32_t			indexCount;
	uint32_t			instanceCount;
} Mtl4CommandDraw;

typedef struct Mtl4CommandDrawIndirect {
	void*				vertexData;
	void*				pixelData;
	void*				indices;
	void*				indirectArgs;

	size_t				preparedIndirectArgsOffset;
} Mtl4CommandDrawIndirect;

typedef struct Mtl4CommandMultiDrawIndirect {
	void*				vertexData;
	size_t				vertexStride;
	void*				pixelData;
	size_t				pixelStride;
	void*				indirectArgs;
	void*				indirectDrawCount;

	size_t				preparedIcbRangeOffset;
} Mtl4CommandMultiDrawIndirect;

typedef struct Mtl4RenderCommand {
	Mtl4RenderCommandType			type;

	Mtl4Pipeline				pipeline;
	Mtl4DepthStencilState			depthStencil;
	Mtl4BlendState				blend;
	void*					textureHeapPtr;

	union {
		Mtl4CommandDraw			draw;
		Mtl4CommandDrawIndirect		drawIndirect;
		Mtl4CommandMultiDrawIndirect	multiDrawIndirect;
	};
} Mtl4RenderCommand;

typedef struct Mtl4CommandRenderPass {
	const GpuRenderPassDesc*	desc;

	bool				requiresPreparation;
	bool				containsMultiDraw;
	bool				containsIndirectDraw;

	CmnChain<Mtl4RenderCommand>	commands;
} Mtl4CommandRenderPass;

typedef struct Mtl4WaitBarrier {
	GpuStageFlags	stages;
	GpuHazardFlags	hazards;
} Mtl4WaitBarrier;

typedef struct Mtl4RenderBarrier {
	Mtl4WaitBarrier	vertex;
	Mtl4WaitBarrier	fragment;
} Mtl4RenderBarrier;

typedef struct Mtl4Command {
	Mtl4CommandType	type;

	union {
		// NOTE: Only used only for compute.
		Mtl4WaitBarrier		barrier;
		// NOTE: Only used for beginRenderPass
		Mtl4RenderBarrier	renderBarrier;
	};

	union {
		Mtl4CommandCopyBufferToBuffer	copyBufferToBuffer;
		Mtl4CommandCopyBufferToTexture	copyBufferToTexture;
		Mtl4CommandCopyTextureToBuffer	copyTextureToBuffer;

		Mtl4CommandDispatch		dispatch;
		Mtl4CommandDispatchIndirect	dispatchIndirect;

		Mtl4CommandSignal		signal;
		Mtl4CommandWait			wait;

		Mtl4CommandRenderPass	renderPass;
	};
} Mtl4Command;

#endif // MTL4_COMMAND_H

