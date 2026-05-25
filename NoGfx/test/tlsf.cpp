#include "test.h"

#include <lib/common/heap_allocator.h>
#include <lib/common/tlsf/tlsf.h>

static void initTlsfPool(Test* test, TlsfPool* pool, size_t totalSize) {
	CmnResult result;
	tlsfInitPool(pool, cmnHeapAllocator(), totalSize, &result);
	TEST_ASSERT(test, result == CMN_SUCCESS);
}

void checkTlsfIndexMappingBoundaries(Test* test) {
	uint32_t fli = 0;
	uint32_t sli = 0;

	tlsfIndexMapping(1, &fli, &sli);
	TEST_ASSERT(test, fli == 0);
	TEST_ASSERT(test, sli == 0);

	tlsfIndexMapping(16, &fli, &sli);
	TEST_ASSERT(test, fli == 0);
	TEST_ASSERT(test, sli == 0);

	tlsfIndexMapping(17, &fli, &sli);
	TEST_ASSERT(test, fli == 0);
	TEST_ASSERT(test, sli == 1);

	tlsfIndexMapping(32, &fli, &sli);
	TEST_ASSERT(test, fli == 1);
	TEST_ASSERT(test, sli == 0);

	tlsfIndexMapping(64, &fli, &sli);
	TEST_ASSERT(test, fli == 2);
	TEST_ASSERT(test, sli == 0);
}

void checkTlsfFirstFreeMappingSelectsSplitBlock(Test* test) {
	TlsfPool pool = {};
	initTlsfPool(test, &pool, 256);

	uint32_t fli = 0;
	uint32_t sli = 0;
	bool requiresSplit = false;
	bool found = tlsfFirstFreeMapping(&pool, 64, &fli, &sli, &requiresSplit);

	TEST_ASSERT(test, found);
	TEST_ASSERT(test, fli == 4);
	TEST_ASSERT(test, sli == 0);
	TEST_ASSERT(test, requiresSplit);
}

void checkTlsfSplitAllocationAndCoalescing(Test* test) {
	TlsfPool pool = {};
	initTlsfPool(test, &pool, 256);

	CmnResult result;
	uint32_t outOffset = 0;
	TlsfAllocation allocation = tlsfAlloc(&pool, 64, 0, &outOffset, &result);
	TEST_ASSERT(test, result == CMN_SUCCESS);
	TEST_ASSERT(test, allocation != nullptr);

	TlsfBlockHeader* block = (TlsfBlockHeader*)allocation;
	TEST_ASSERT(test, block->size == 64);
	TEST_ASSERT(test, block->offset == 0);
	TEST_ASSERT(test, block->isFree == false);
	TEST_ASSERT(test, block->prevPhys == nullptr);
	TEST_ASSERT(test, block->nextPhys != nullptr);
	TEST_ASSERT(test, block->nextFree == nullptr);
	TEST_ASSERT(test, block->prevFree == nullptr);

	TlsfBlockHeader* remainder = block->nextPhys;
	TEST_ASSERT(test, remainder->size == 192);
	TEST_ASSERT(test, remainder->offset == 64);
	TEST_ASSERT(test, remainder->prevPhys == block);
	TEST_ASSERT(test, remainder->nextPhys == nullptr);
	TEST_ASSERT(test, remainder->isFree == true);

	uint32_t fli = 0;
	uint32_t sli = 0;
	tlsfIndexMapping(192, &fli, &sli);
	TEST_ASSERT(test, pool.freeBitmask == (1ull << fli));
	TEST_ASSERT(test, pool.blockMaps[fli].freeBitmask == (1ull << sli));
	TEST_ASSERT(test, pool.blockMaps[fli].firstFreeBlocks[sli] == remainder);

	tlsfFree(&pool, allocation);

	tlsfIndexMapping(256, &fli, &sli);
	TEST_ASSERT(test, block->size == 256);
	TEST_ASSERT(test, block->offset == 0);
	TEST_ASSERT(test, block->prevPhys == nullptr);
	TEST_ASSERT(test, block->nextPhys == nullptr);
	TEST_ASSERT(test, block->isFree == true);
	TEST_ASSERT(test, pool.freeBitmask == (1ull << fli));
	TEST_ASSERT(test, pool.blockMaps[fli].freeBitmask == (1ull << sli));
	TEST_ASSERT(test, pool.blockMaps[fli].firstFreeBlocks[sli] == block);
}

void checkTlsfExactFitAllocationAndOOM(Test* test) {
	TlsfPool pool = {};
	initTlsfPool(test, &pool, 64);

	CmnResult result;
	uint32_t outOffset = 0;
	TlsfAllocation allocation = tlsfAlloc(&pool, 64, 0, &outOffset, &result);
	TEST_ASSERT(test, result == CMN_SUCCESS);
	TEST_ASSERT(test, allocation != nullptr);

	uint32_t fli = 0;
	uint32_t sli = 0;
	tlsfIndexMapping(64, &fli, &sli);
	TEST_ASSERT(test, pool.freeBitmask == 0);
	TEST_ASSERT(test, pool.blockMaps[fli].freeBitmask == 0);
	TEST_ASSERT(test, pool.blockMaps[fli].firstFreeBlocks[sli] == nullptr);

	TlsfAllocation failedAllocation = tlsfAlloc(&pool, 1, 0, &outOffset, &result);
	TEST_ASSERT(test, failedAllocation == nullptr);
	TEST_ASSERT(test, result == CMN_OUT_OF_MEMORY);

	tlsfFree(&pool, allocation);

	TEST_ASSERT(test, pool.freeBitmask == (1ull << fli));
	TEST_ASSERT(test, pool.blockMaps[fli].freeBitmask == (1ull << sli));
	TEST_ASSERT(test, pool.blockMaps[fli].firstFreeBlocks[sli] != nullptr);
}

void checkTlsfAlignedAllocation(Test* test) {
	TlsfPool pool = {};
	initTlsfPool(test, &pool, 256);

	CmnResult result;
	uint32_t outOffset = 0;
	TlsfAllocation allocation = tlsfAlloc(&pool, 16, 32, &outOffset, &result);
	TEST_ASSERT(test, result == CMN_SUCCESS);
	TEST_ASSERT(test, allocation != nullptr);

	TlsfBlockHeader* block = (TlsfBlockHeader*)allocation;
	TEST_ASSERT(test, (outOffset % 32) == 0);
	TEST_ASSERT(test, outOffset >= block->offset);
	TEST_ASSERT(test, outOffset < (block->offset + block->size));

	tlsfFree(&pool, allocation);

	uint32_t fli = 0;
	uint32_t sli = 0;
	tlsfIndexMapping(256, &fli, &sli);
	TEST_ASSERT(test, pool.freeBitmask == (1ull << fli));
	TEST_ASSERT(test, pool.blockMaps[fli].freeBitmask == (1ull << sli));
	TEST_ASSERT(test, pool.blockMaps[fli].firstFreeBlocks[sli] != nullptr);
}
