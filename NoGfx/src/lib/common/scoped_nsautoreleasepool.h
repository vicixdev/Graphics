#ifndef CMN_SCOPEDNSAUTORELEASEPOOL_H
#define CMN_SCOPEDNSAUTORELEASEPOOL_H

#include <lib/common/common.h>
#ifndef CMN_PLATFORM_DARWIN
	#panic CmnScopedNSAutoreleasePool is darwin-exclusive.
#endif

#include <Foundation/Foundation.h>

typedef class CmnScopedNSAutoreleasePool {
public:
	NSAutoreleasePool* pool;

	CmnScopedNSAutoreleasePool(void) {
		this->pool = [[NSAutoreleasePool alloc] init];
	}

	~CmnScopedNSAutoreleasePool(void) {
		[this->pool release];
	}
} CmnScopedNSAutoreleasePool;

#endif // CMN_SCOPEDNSAUTORELEASEPOOL_H

