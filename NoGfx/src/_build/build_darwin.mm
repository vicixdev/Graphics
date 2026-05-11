#include <lib/common/language.h>

#ifndef CMN_LANGUAGE_OBJECTIVECPP
	#error NoGfx requires a compiler supporting Objective-C++ when targeting macOs.
#endif

#include "personality.cpp"

#include <lib/common/page_posix.cpp>
#include <lib/common/futex_darwin.cpp>
#include <lib/common/arena.cpp>
#include <lib/common/pool.cpp>
#include <lib/common/mutex.cpp>
#include <lib/common/condition.cpp>
#include <lib/common/rw_mutex.cpp>
#include <lib/common/storage_sync.cpp>
#include <lib/common/memory.cpp>
#include <lib/common/heap_allocator.cpp>

#include <lib/lib.cpp>
#include <lib/layers.cpp>
#include <lib/layers_darwin.cpp>

#include <lib/metal4/layers.cpp>
#include <lib/metal4/tables.cpp>
#include <lib/metal4/context.mm>
#include <lib/metal4/device.mm>
#include <lib/metal4/allocation.mm>
#include <lib/metal4/textures.mm>
#include <lib/metal4/pipelines.mm>
#include <lib/metal4/queue.mm>
#include <lib/metal4/command_buffers.mm>
#include <lib/metal4/events.mm>
#include <lib/metal4/semaphores.mm>
#include <lib/metal4/validation.mm>
#include <lib/metal4/deletion_manager.cpp>

#include <lib/metal4/shaders/wait.cpp>
#include <lib/metal4/shaders/signal.cpp>

