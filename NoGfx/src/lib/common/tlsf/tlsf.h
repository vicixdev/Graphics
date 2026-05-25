#ifndef CMN_TLSF_H
#define CMN_TLSF_H

#include <assert.h>
#include <lib/common/common.h>
#include <lib/common/allocator.h>

#define TLSF_MEMORY_POOL_SIZE (64 * 1024 * 1024)

// TLSF_FLI == min(log_2(block_size), 32)
#define TLSF_FLI 26

#define TLSF_SLI_DIVISIONS 16
// TLSF_SLI == log_2(SLI_DIVISIONS)
#define TLSF_SLI 4

// Minimum block size is 16 bytes.
#define TLSF_MBS 4

#define TLSF_MAX_SLI 8

typedef const struct TlsfBlockHeader* TlsfAllocation;

typedef struct TlsfBlockHeader {
	uint32_t		size : 31;
	bool			isFree : 1;
	uint32_t		offset;
	TlsfBlockHeader*	prevPhys;
	TlsfBlockHeader*	nextPhys;
	TlsfBlockHeader*	nextFree;
	TlsfBlockHeader*	prevFree;
} TlsfBlockHeader;
static_assert(sizeof(TlsfBlockHeader) <= 64, "TlsfBlockHeader should be 32 bytes.");

// NOTE: This is equivalent to a second level block.
typedef struct TlsfBlockMap {
	TlsfBlockHeader*	firstFreeBlocks[TLSF_SLI_DIVISIONS];
	uint64_t		freeBitmask;
} TlsfBlockMap;

typedef struct TlsfPool {
	CmnAllocator	blockAllocator;

	TlsfBlockMap	blockMaps[TLSF_FLI - TLSF_MBS];
	uint64_t	freeBitmask;
} TlsfPool;

void tlsfInitPool(TlsfPool* pool, CmnAllocator allocator, size_t totalSize, CmnResult* result);

void tlsfIndexMapping(size_t size, uint32_t* outFli, uint32_t* outSli);
bool tlsfIsFree(TlsfPool* pool, uint32_t fli, uint32_t sli);
bool tlsfFirstFreeMapping(TlsfPool* pool, uint32_t size, uint32_t* outFli, uint32_t* outSli, bool* requiresSplit);

void tlsfInsertFreeBlock(TlsfPool* pool, uint32_t fli, uint32_t sli, TlsfBlockHeader* block);
void tlsfRemoveFreeBlock(TlsfPool* pool, TlsfBlockHeader* block);
TlsfBlockHeader* tlsfRemoveFreeBlock(TlsfPool* pool, uint32_t fli, uint32_t sli);

TlsfAllocation tlsfAlloc(TlsfPool* pool, uint32_t size, uint32_t alignment, uint32_t* outOffset, CmnResult* result);
void tlsfFree(TlsfPool* pool, TlsfAllocation allocation);

#endif // CMN_TLSF_H
