#include "tlsf.h"

void tlsfIndexMapping(size_t size, uint32_t* outFli, uint32_t* outSli) {
	if (size <= 16) {
		*outFli = 0;
		*outSli = (size - 1) / 16;
		return;
	}

	uint32_t fli = 31 - __builtin_clz(size);
	uint32_t sli = (size >> (fli - TLSF_SLI)) & ((1 << TLSF_SLI) - 1);

	*outFli = fli - TLSF_MBS;
	*outSli = sli;
}

bool tlsfIsFree(TlsfPool* pool, uint32_t fli, uint32_t sli) {
	return pool->freeBitmask & (1ull << fli) &&
		(pool->blockMaps[fli].freeBitmask & (1ull << sli));
}

bool tlsfFirstFreeMapping(TlsfPool* pool, uint32_t size, uint32_t* outFli, uint32_t* outSli, bool* requiresSplit) {
	uint32_t fli, sli;
	tlsfIndexMapping(size, &fli, &sli);

	*requiresSplit = false;

	if (!tlsfIsFree(pool, fli, sli)) {
		int nextFli = __builtin_ffsll(pool->freeBitmask & (~0ull << fli));
		if (nextFli == 0) {
			// No free blocks large enough.
			*outFli = 0;
			*outSli = 0;
			*requiresSplit = false;
			return false;
		}

		fli = (uint32_t)(nextFli - 1);

		int nextSli = __builtin_ffsll(pool->blockMaps[fli].freeBitmask);
		assert(nextSli != 0 && "If there is a free block in this FLI, there should be a free block in this SLI.");
		sli = (uint32_t)(nextSli - 1);

		*requiresSplit = true;
	}

	*outFli = fli;
	*outSli = sli;
	return true;
}

void tlsfInsertFreeBlock(TlsfPool* pool, uint32_t fli, uint32_t sli, TlsfBlockHeader* block) {
	block->isFree = true;
	block->nextFree = pool->blockMaps[fli].firstFreeBlocks[sli];
	block->prevFree = nullptr;

	if (pool->blockMaps[fli].firstFreeBlocks[sli] != nullptr) {
		pool->blockMaps[fli].firstFreeBlocks[sli]->prevFree = block;
	}

	pool->blockMaps[fli].firstFreeBlocks[sli] = block;
	pool->blockMaps[fli].freeBitmask |= (1ull << sli);
	pool->freeBitmask |= (1ull << fli);
}

void tlsfRemoveFreeBlock(TlsfPool* pool, TlsfBlockHeader* block) {
	uint32_t fli, sli;
	tlsfIndexMapping(block->size, &fli, &sli);

	if (block->prevFree != nullptr) {
		block->prevFree->nextFree = block->nextFree;
	} else {
		pool->blockMaps[fli].firstFreeBlocks[sli] = block->nextFree;
	}

	if (block->nextFree != nullptr) {
		block->nextFree->prevFree = block->prevFree;
	}

	if (pool->blockMaps[fli].firstFreeBlocks[sli] == nullptr) {
		pool->blockMaps[fli].freeBitmask &= ~(1ull << sli);
		if (pool->blockMaps[fli].freeBitmask == 0) {
			pool->freeBitmask &= ~(1ull << fli);
		}
	}

	block->nextFree = nullptr;
	block->prevFree = nullptr;
}

TlsfBlockHeader* tlsfRemoveFreeBlock(TlsfPool* pool, uint32_t fli, uint32_t sli) {
	TlsfBlockHeader* block = pool->blockMaps[fli].firstFreeBlocks[sli];
	tlsfRemoveFreeBlock(pool, block);

	return block;
}

void tlsfInitPool(TlsfPool* pool, CmnAllocator allocator, size_t totalSize, CmnResult* result) {
	assert(totalSize <= TLSF_MEMORY_POOL_SIZE);

	CmnResult localResult;

	*pool = {};
	pool->blockAllocator = allocator;

	TlsfBlockHeader* initialBlock = cmnAlloc<TlsfBlockHeader>(
		pool->blockAllocator,
		1,
		&localResult
	);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}

	initialBlock->size = totalSize;
	initialBlock->offset = 0;

	uint32_t fli, sli;
	tlsfIndexMapping(totalSize, &fli, &sli);
	tlsfInsertFreeBlock(pool, fli, sli, initialBlock);

	CMN_SET_RESULT(result, CMN_SUCCESS);
}

TlsfAllocation tlsfAlloc(TlsfPool* pool, uint32_t size, uint32_t alignment, uint32_t* outOffset, CmnResult* result) {
	CmnResult localResult;

	if (alignment > 0) {
		size += alignment;
	}

	uint32_t fli, sli;
	bool requiresSplit;

	bool found = tlsfFirstFreeMapping(pool, size, &fli, &sli, &requiresSplit);
	if (!found) {
		CMN_SET_RESULT(result, CMN_OUT_OF_MEMORY);
		return nullptr;
	}

	TlsfBlockHeader* block = tlsfRemoveFreeBlock(pool, fli, sli);
	TlsfBlockHeader* originalNextPhys = block->nextPhys;
	uint32_t originalSize = block->size;

	block->isFree = false;

	if (requiresSplit) {
		TlsfBlockHeader* remainingBlock = cmnAlloc<TlsfBlockHeader>(
			pool->blockAllocator,
			1,
			&localResult
		);
		if (localResult != CMN_SUCCESS) {
			// NOTE: We failed to split the block, but the allocation itself did not fail.
			CMN_SET_RESULT(result, CMN_SUCCESS);
			return block;
		}

		block->size = size;
		block->nextPhys = remainingBlock;

		remainingBlock->size = originalSize - size;
		remainingBlock->offset = block->offset + size;
		remainingBlock->prevPhys = block;
		remainingBlock->nextPhys = originalNextPhys;

		if (originalNextPhys != nullptr) {
			originalNextPhys->prevPhys = remainingBlock;
		}

		uint32_t remainingFli, remainingSli;
		tlsfIndexMapping(remainingBlock->size, &remainingFli, &remainingSli);
		tlsfInsertFreeBlock(pool, remainingFli, remainingSli, remainingBlock);
	}

	if (alignment > 0) {
		uint32_t misalignment = (block->offset % alignment);
		uint32_t adjustment = alignment - misalignment;
		*outOffset = block->offset + adjustment;
	} else {
		*outOffset = block->offset;
	}

	CMN_SET_RESULT(result, CMN_SUCCESS);
	return block;
}

void tlsfFree(TlsfPool* pool, TlsfAllocation allocation) {
	TlsfBlockHeader* block = (TlsfBlockHeader*)allocation;
	TlsfBlockHeader* mergedBlock = block;

	if (block->prevPhys != nullptr && block->prevPhys->isFree) {
		// Coalesce with previous block.
		TlsfBlockHeader* prevBlock = block->prevPhys;
		tlsfRemoveFreeBlock(pool, prevBlock);
		prevBlock->size += block->size;
		prevBlock->nextPhys = block->nextPhys;
		mergedBlock = prevBlock;

		if (block->nextPhys != nullptr) {
			block->nextPhys->prevPhys = prevBlock;
		}

		cmnFree(pool->blockAllocator, block);
	}

	if (mergedBlock->nextPhys != nullptr && mergedBlock->nextPhys->isFree) {
		TlsfBlockHeader* nextBlock = mergedBlock->nextPhys;
		tlsfRemoveFreeBlock(pool, nextBlock);
		mergedBlock->size += nextBlock->size;
		mergedBlock->nextPhys = nextBlock->nextPhys;

		if (nextBlock->nextPhys != nullptr) {
			nextBlock->nextPhys->prevPhys = mergedBlock;
		}

		cmnFree(pool->blockAllocator, nextBlock);
	}

	uint32_t fli, sli;
	tlsfIndexMapping(mergedBlock->size, &fli, &sli);
	tlsfInsertFreeBlock(pool, fli, sli, mergedBlock);
}
