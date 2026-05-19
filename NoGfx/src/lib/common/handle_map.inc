template <typename T>
bool cmninternalIsValid(const CmnHandleMap<T>* map, CmnHandle handle) {
	return handle.index < map->buckets.length &&
		map->buckets[handle.index].isInUse &&
		handle.generation == map->buckets[handle.index].generation;
}

template <typename T>
uint32_t cmninternalHandleMapGetNextFreeBucket(CmnHandleMap<T>* map, CmnResult* result) {
	CmnResult localResult;

	uint32_t firstFreeBucketIndex = map->firstFree;
	if (firstFreeBucketIndex == UINT32_MAX) {
		CMN_SET_RESULT(result, CMN_OUT_OF_RESOURCE_SLOTS);
		return UINT32_MAX;
	}

	for (;;) {
		if (firstFreeBucketIndex >= map->buckets.length) {
			break;
		}

		CmnHandleMapBucket<T>* bucket = &map->buckets[firstFreeBucketIndex];

		if (bucket->generation == UINT32_MAX) {
			firstFreeBucketIndex = bucket->nextFreeIndex;
		} else {
			break;
		}
	}


	if (firstFreeBucketIndex >= map->buckets.length) {
		firstFreeBucketIndex = map->buckets.length;

		CmnHandleMapBucket<T> newBucket;
		newBucket.isInUse	= false,
		newBucket.generation	= 0,
		newBucket.nextFreeIndex	= firstFreeBucketIndex + 1,

		cmnAppend(&map->buckets, newBucket, &localResult);
		if (localResult != CMN_SUCCESS) {
			CMN_SET_RESULT(result, localResult);
			return UINT32_MAX;
		}
	}

	CmnHandleMapBucket<T>* bucket = &map->buckets[firstFreeBucketIndex];
	map->firstFree = bucket->nextFreeIndex;

	CMN_SET_RESULT(result, CMN_SUCCESS);
	return firstFreeBucketIndex;
}

template <typename T>
void cmnCreateHandleMap(CmnHandleMap<T>* map, CmnAllocator backingAllocator, T defaultElement, CmnResult* result) {
	CmnResult localResult;
	*map = {};

	cmnCreateExponentialArray(&map->buckets, backingAllocator, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}

	CmnHandleMapBucket<T> firstBucket;
	firstBucket.isInUse		= false,
	firstBucket.generation		= 0,
	firstBucket.nextFreeIndex	= 1,

	cmnAppend(&map->buckets, firstBucket, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return;
	}

	map->firstFree = 0;
	map->defaultElement = defaultElement;

	CMN_SET_RESULT(result, CMN_SUCCESS);
}

template <typename T>
CmnHandle cmnInsert(CmnHandleMap<T>* map, const T& element, CmnResult* result) {
	CmnResult localResult;

	uint32_t freeBucketIndex = cmninternalHandleMapGetNextFreeBucket(map, &localResult);
	if (localResult != CMN_SUCCESS) {
		CMN_SET_RESULT(result, localResult);
		return {};
	}

	CmnHandleMapBucket<T>* bucket = &map->buckets[freeBucketIndex];
	bucket->generation++;
	bucket->isInUse = true;
	bucket->element = element;

	CMN_SET_RESULT(result, CMN_SUCCESS);
	return CmnHandle{
		/*index=*/	freeBucketIndex,
		/*generation=*/	bucket->generation,
	};
}

template <typename T>
bool cmnIsValid(const CmnHandleMap<T>* map, CmnHandle handle) {
	return cmninternalIsValid<T>(map, handle);
}

template <typename T>
T& cmnGet(CmnHandleMap<T>* map, CmnHandle handle, bool* wasHandleValid) {
	if (!cmninternalIsValid(map, handle)) {
		if (wasHandleValid != nullptr) {
			*wasHandleValid = false;
		}

		return map->defaultElement;
	} else {
		if (wasHandleValid != nullptr) {
			*wasHandleValid = true;
		}

		return map->buckets[handle.index].element;
	}
}

template <typename T>
void cmnRemove(CmnHandleMap<T>* map, CmnHandle handle) {
	if (!cmninternalIsValid(map, handle)) {
		return;
	}

	CmnHandleMapBucket<T>* bucket = &map->buckets[handle.index];

	bucket->isInUse = false;
	bucket->nextFreeIndex = map->firstFree;

	map->firstFree = handle.index;
}

template <typename T>
void cmnCreateHandleMapIterator(CmnHandleMap<T>* map, CmnHandleMapIterator<T>* iter) {
	iter->map = map;
	iter->currentBucketIndex = 0;
}

template <typename T>
bool cmnIterate(CmnHandleMapIterator<T>* iter, T** value) {
	while (iter->currentBucketIndex < iter->map->buckets.length) {
		CmnHandleMapBucket<T>& bucket = iter->map->buckets[iter->currentBucketIndex];
		if (bucket.isInUse) {
			*value = &bucket.element;
			iter->currentBucketIndex++;
			return true;
		}

		iter->currentBucketIndex++;
	}

	return false;
}
