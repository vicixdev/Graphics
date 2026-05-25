#include "test.h"
#include "test.cpp"

#include "page.cpp"
#include "arena.cpp"
#include "synchronization.cpp"
#include "pointer_map.cpp"
#include "hash_map.cpp"
#include "exponential_array.cpp"
#include "pool.cpp"
#include "chain.cpp"
#include "keyed_chain.cpp"
#include "heap_allocator.cpp"
#include "handle_map.cpp"
#include "handle_map_static.cpp"
#include "btree.cpp"
#include "storage_sync.cpp"
#include "tlsf.cpp"

#include "gpu_common.cpp"
#include "gpu_init.cpp"
#include "gpu_allocation.cpp"
#include "gpu_texture.cpp"
#include "gpu_pipeline.cpp"
#include "gpu_synchronization.cpp"

TestRecord gCommonTests[] = {
	{ "Can access page memory",					canAccessPageMemory				},

	{ "Check for arena memory coherency",				checkForArenaMemoryCoherency			},

	{ "Check for exponential array data coherency",			checkForExponentialArrayDataCoherency		},
	{ "Check for exponential array memory coherency",		checkForExponentialArrayMemoryCoherency		},
	{ "Check for exponential array data coherency (S=3)", 		checkForExponentialArrayDataCoherency_S3	},
	{ "Check for exponential array memory coherency (S=3)", 	checkForExponentialArrayMemoryCoherency_S3	},

	{ "Check for pool initial memory setup",			checkForPoolInitialMemorySetup			},
	{ "Check for block reusage in pools",				checkPoolBlockReusage				},
	{ "Check pool out of memory behaviour",				checkPoolOOMBehaviour				},
	{ "Check for pool behavious with uninitialized locations",	checkPoolUninitializedLocations			},

	{ "Check chain creation and insertion", 			checkChainCreationAndInsertion			},
	{ "Check chain contains and removal", 				checkChainContainsAndRemove			},
	{ "Check chain iteration", 					checkChainIteration				},

	{ "Check keyed chain creation and insertion", 			checkKeyedChainCreationAndInsertion 		},
	{ "Check keyed chain overwrite and removal", 			checkKeyedChainOverwriteAndRemoval 		},
	{ "Check keyed chain iteration", 				checkKeyedChainIteration 			},

	{ "Check heap raw allocation is zeroed",			checkHeapRawAllocationIsZeroed			},
	{ "Check heap typed allocation overloads",			checkHeapTypedAllocationOverloads		},
	{ "Check heap raw realloc preserves and zeros",			checkHeapRawReallocPreservesAndZeros		},
	{ "Check heap typed realloc preserves and zeros",		checkHeapTypedReallocPreservesAndZeros		},
	{ "Check heap aligned raw allocation",				checkHeapAlignedRawAllocation			},

	{ "Check TLSF index mapping boundaries",			checkTlsfIndexMappingBoundaries			},
	{ "Check TLSF first free mapping selects split block",		checkTlsfFirstFreeMappingSelectsSplitBlock	},
	{ "Check TLSF split allocation and coalescing",			checkTlsfSplitAllocationAndCoalescing		},
	{ "Check TLSF exact fit allocation and OOM",			checkTlsfExactFitAllocationAndOOM		},
	{ "Check TLSF aligned allocation", 				checkTlsfAlignedAllocation				},

	{ "Check for handle map data coherency",			checkForHandleMapDataCoherency			},
	{ "Check for handle map bucket reusage",			checkForHandleMapBucketReusage			},
	{ "Check for handle map behaviour on generation overflow",	checkForHandleMapGenerationOverflowBehaviour	},
	{ "Check for handle map behaviour on index overflow",		checkForHandleMapIndexOverflowBehaviour		},
	{ "Check for handle map behaviour on invalid handles",		checkForHandleMapInvalidHandleBehaviour		},

	{ "Check static handle map data coherency",			checkForStaticHandleMapDataCoherency		},
	{ "Check static handle map bucket reusage", 			checkForStaticHandleMapBucketReusage		},
	{ "Check static handle map generation overflow behaviour", 	checkForStaticHandleMapGenerationOverflowBehaviour	},
	{ "Check static handle map index overflow behaviour", 		checkForStaticHandleMapIndexOverflowBehaviour	},
	{ "Check static handle map invalid handle behaviour", 		checkForStaticHandleMapInvalidHandleBehaviour	},

	{ "Check B-tree creation and initial root state",		checkBTreeCreation				},
	{ "Check B-tree insertion of keys and contains functionality",	checkBTreeInsertAndContains			},
	{ "Check B-tree get functionality with found and default element", checkBTreeGet				},
	{ "Check B-tree removal of keys from leaf nodes",		checkBTreeRemoveLeaf				},
	{ "Check B-tree removal of keys from non-leaf/internal nodes",	checkBTreeRemoveNonLeaf				},
	{ "Check B-tree root split when inserting enough keys",		checkBTreeRootSplit				},
	{ "Check B-tree predecessor and successor key retrieval",	checkBTreePredecessorSuccessor			},

	{ "Check pointer map creation and initial state",		checkPointerMapCreation				},
	{ "Check pointer map insert and contains",			checkPointerMapInsertAndContains		},
	{ "Check pointer map get with found and default",		checkPointerMapGet				},
	{ "Check pointer map removal of keys",				checkPointerMapRemove				},
	{ "Check pointer map reserve and rehash",			checkPointerMapReserveAndRehash			},

	{ "Check hash map creation and initial state",			checkHashMapCreation				},
	{ "Check hash map insert contains and get",			checkHashMapInsertContainsAndGet		},
	{ "Check hash map overwrite does not grow length",		checkHashMapOverwriteDoesNotGrowLength		},
	{ "Check hash map remove and reuse deleted slots",		checkHashMapRemoveAndReuseDeletedSlots		},
	{ "Check hash map reserve and rehash",				checkHashMapReserveAndRehash			},

	{ "Check mutex mutual exclusion with pthreads",			checkMutexMutualExclusionWithPthreads		},
	{ "Check mutex try-lock while locked",				checkMutexTryLockWhileLocked			},
	{ "Check condition signal wakes waiter",			checkConditionSignalWakesWaiter			},
	{ "Check condition wait timeout",				checkConditionWaitTimeout			},
	{ "Check RW mutex allows concurrent readers",			checkRWMutexAllowsConcurrentReaders		},
	{ "Check RW mutex write exclusion",				checkRWMutexWriteExclusion			},

	{ "Check semaphore allows maximum concurrent acquisitions",	checkSemaphoreAllowsMaximumConcurrentAcquisitions	},
	{ "Check semaphore try-wait fails when count is zero",	checkSemaphoreTryWaitFailsWhenCountIsZero	},

	{ "Check storage sync acquire/release for valid handles", 	checkStorageSyncAcquireAndReleaseValidHandle	},
	{ "Check storage sync invalid handles do not increment users", 	checkStorageSyncInvalidHandleDoesNotIncrementUsers	},
	{ "Check storage sync deletion waits for active users", 	checkStorageSyncDeletionWaitsForActiveUsers	},
};

TestRecord gNoGfxTests[] = {
	{ "Check GPU initialization and deinitialization",		checkGpuInitAndDeinit				},
	{ "Check GPU invalid backend handling",				checkGpuInvalidBackend				},
	{ "Check GPU device enumeration",				checkGpuEnumerateDevices			},
	{ "Check GPU device selection",					checkGpuSelectDevice				},
	{ "Check GPU invalid device selection",				checkGpuSelectInvalidDevice			},
	{ "Check GPU double device selection handling",			checkGpuDoubleDeviceSelection			},

	{ "Check GPU memory allocation and free",			checkGpuMallocAndFree				},
	{ "Check GPU memory allocation and free for GPU-only memory",	checkGpuMallocAndFreeGpuMemory			},
	{ "Check GPU free with invalid pointer",			checkGpuFreeInvalidPointer			},
	{ "Check GPU host to device pointer mapping",			checkGpuHostToDevicePointer			},
	{ "Check GPU host to device pointer fails for GPU-only memory",	checkGpuHostToDevicePointerOnGpuMemory		},
	{ "Check GPU host to device pointer mapping with offset",	checkGpuHostToDevicePointerWithOffset		},
	{ "Check GPU allocation create/destroy across threads", 	checkGpuAllocationCreatedAndDestroyedOnDifferentThreads },
	{ "Check GPU concurrent allocation stress on CPU memory", 	checkGpuConcurrentAllocationStressOnCpuMemory	},
	{ "Check GPU concurrent allocation stress on GPU memory", 	checkGpuConcurrentAllocationStressOnGpuMemory	},
	{ "Check GPU concurrent host pointer stress", 			checkGpuConcurrentHostPointerStress		},
	{ "Check GPU deferred allocation deletion threshold flush", 	checkGpuDeferredAllocationDeletionThresholdFlush	},

	{ "Check GPU texture size and alignment calculation", 		checkGpuTextureSizeAlign			},
	{ "Check GPU texture size and alignment invalid descriptor", 	checkGpuTextureSizeAlignInvalidDesc		},
	{ "Check GPU texture creation", 				checkGpuCreateTexture				},
	{ "Check GPU texture creation on CPU allocation", 		checkGpuCreateTextureOnCpuAllocation		},
	{ "Check GPU texture creation invalid descriptor", 		checkGpuCreateTextureInvalidDesc		},
	{ "Check GPU texture view descriptor creation", 		checkGpuTextureViewDescriptor			},
	{ "Check GPU RW texture view descriptor creation", 		checkGpuRWTextureViewDescriptor			},
	{ "Check GPU texture view descriptor invalid texture", 		checkGpuTextureViewDescriptorInvalidTexture	},
	{ "Check GPU texture view descriptor invalid descriptor", 	checkGpuTextureViewDescriptorInvalidDesc	},
	{ "Check GPU texture create/destroy across threads", 		checkGpuTextureCreatedAndBackingFreedOnDifferentThreads },
	{ "Check GPU concurrent texture stress", 			checkGpuConcurrentTextureStress			},
	{ "Check GPU deferred texture deletion threshold flush", 	checkGpuDeferredTextureDeletionThresholdFlush	},

	{ "Check GPU compute pipeline creation", 			checkGpuCreateComputePipeline			},
	{ "Check GPU compute pipeline creation with constants", 	checkGpuCreateComputePipelineWithConstants	},
	{ "Check GPU compute pipeline invalid IR handling", 		checkGpuCreateComputePipelineInvalidIr		},
	{ "Check GPU render pipeline creation", 			checkGpuCreateRenderPipeline			},
	{ "Check GPU render pipeline creation with constants", 		checkGpuCreateRenderPipelineWithConstants	},
	{ "Check GPU concurrent pipeline stress", 			checkGpuConcurrentPipelineStress		},

	{ "Check basic signal-based synchronization",			gpuTestSignalWritingOnGpuPtr			},
};

int main(void) {
	size_t commonTestCount = sizeof(gCommonTests) / sizeof(*gCommonTests);
	doTests("Common utilities", gCommonTests, commonTestCount);

	size_t noGfxTestCount = sizeof(gNoGfxTests) / sizeof(*gNoGfxTests);
	doTests("No Graphics", gNoGfxTests, noGfxTestCount);

	return 0;
}

