#if !defined(METAL4_RENDERER) && !defined(NOGFX_RENDERER)
        #error Please specity either METAL4_RENDERER or NOGFX_RENDERER to build the program
#endif

#include "main.c"
#include "timer.c"
#include "renderer_metal4.m"
#include "renderer_nogfx.c"
