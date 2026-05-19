template <typename T, size_t N, size_t S>
void cmnCreateExponentialArray(CmnExponentialArray<T, N, S>* array, CmnAllocator backingAllocator, CmnResult* result) {
	array->backingAllocator	= backingAllocator;
	memset(array->buckets, 0, sizeof(array->buckets));
	array->length		= 0;
	array->last_filled_bucket = 0;

	array->buckets[0]	= cmnAlloc<T>(array->backingAllocator, (1ULL << S), result);
}

template <typename T, size_t N, size_t S>
bool cmnAppend(CmnExponentialArray<T, N, S>* array, const T& value, CmnResult* result) {
	size_t idx = array->length;

	if (!cmnResize<T, N, S>(array, array->length + 1, result)) {
		return false;
	}

	cmnSet<T, N, S>(array, idx, value);
	CMN_SET_RESULT(result, CMN_SUCCESS);
	return true;
}

template <typename T, size_t N, size_t S>
bool cmnResize(CmnExponentialArray<T, N, S>* array, size_t length, CmnResult* result) {
	if (array->length >= length) {
		CMN_SET_RESULT(result, CMN_SUCCESS);
		return true;
	}

	size_t bucketIndex, elementIndex;
	cmnDecomposeExponentialArrayIndex(length, S, &bucketIndex, &elementIndex);

	if (bucketIndex >= N) {
		CMN_SET_RESULT(result, CMN_OUT_OF_MEMORY);
		return false;
	}

	if (bucketIndex <= array->last_filled_bucket) {
		array->length = length;

		CMN_SET_RESULT(result, CMN_SUCCESS);
		return true;
	}

	for (size_t i = array->last_filled_bucket; i <= bucketIndex; i++) {
		if (array->buckets[i] != nullptr) {
			continue;
		}

		size_t allocCount;
		if (i == 0) {
			allocCount = (1ULL << S);
		} else {
			allocCount = (1ULL << (S + i - 1));
		}

		array->buckets[i] = cmnAlloc<T>(
			array->backingAllocator,
			allocCount,
			result
		);
		if (array->buckets[i] == nullptr) {
			return false;
		}

		array->last_filled_bucket = i;
	}

	array->length = length;

	CMN_SET_RESULT(result, CMN_SUCCESS);
	return true;
}

template <typename T, size_t N, size_t S>
void cmnSet(CmnExponentialArray<T, N, S>* array, size_t index, const T& value) {
	assert(index <= array->length);

	size_t bucketIndex, elementIndex;
	cmnDecomposeExponentialArrayIndex(index, S, &bucketIndex, &elementIndex);

	array->buckets[bucketIndex][elementIndex] = value;
}

template <typename T, size_t N, size_t S>
T& cmnGet(CmnExponentialArray<T, N, S>* array, size_t index) {
	assert(index <= array->length);

	size_t bucketIndex, elementIndex;
	cmnDecomposeExponentialArrayIndex(index, S, &bucketIndex, &elementIndex);

	return array->buckets[bucketIndex][elementIndex];
}

template <typename T, size_t N, size_t S>
T& cmnLast(CmnExponentialArray<T, N, S>* array) {
	assert(array->length > 0);

	return (*array)[array->length - 1];
}

template <typename T, size_t N, size_t S>
void cmnPop(CmnExponentialArray<T, N, S>* array) {
	if (array->length == 0) {
		return;
	}

	array->length--;
}

template <typename T, size_t N, size_t S>
void cmnCreateExponentialArrayIterator(CmnExponentialArray<T, N, S>* array, CmnExponentialArrayIterator<T, N, S>* iter) {
	iter->array = array;
	iter->currentIndex = 0;
}

template <typename T, size_t N, size_t S>
bool cmnIterate(CmnExponentialArrayIterator<T, N, S>* iter, T** value) {
	if (iter->currentIndex >= iter->array->length) {
		return false;
	}

	*value = &(*iter->array)[iter->currentIndex];
	iter->currentIndex++;
	return true;
}

inline void cmnDecomposeExponentialArrayIndex(size_t index, size_t firstBucketBitCount, size_t* bucketIndex, size_t* elementIndex) {
	size_t start = firstBucketBitCount;

	size_t indexShift = index >> start;

	if (indexShift == 0) {
		*bucketIndex = 0;
	} else {
		*bucketIndex = CMN_EXPONENTIALARRAY_POINTER_SIZE - __builtin_clzll(indexShift);
	}

	if (*bucketIndex == 0) {
		*elementIndex = index;
	} else {
		size_t bucketBits = start + *bucketIndex - 1;
		*elementIndex = index & ((1ULL << bucketBits) - 1);
	}
}

