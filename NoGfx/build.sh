#!/usr/bin/env sh

set -e

xcrun -sdk macosx metal -c ./src/lib/metal4/shaders/wait.metal -o ./build/wait.air
xcrun -sdk macosx metallib ./build/wait.air -o ./build/wait.metallib

xcrun -sdk macosx metal -c ./src/lib/metal4/shaders/signal.metal -o ./build/signal.air
xcrun -sdk macosx metallib ./build/signal.air -o ./build/signal.metallib

./tools/bin2cpp.py ./build/wait.metallib -o ./src/lib/metal4/shaders/wait.cpp -H ./src/lib/metal4/shaders/wait.h -v gMtl4WaitKernelLib
./tools/bin2cpp.py ./build/signal.metallib -o ./src/lib/metal4/shaders/signal.cpp -H ./src/lib/metal4/shaders/signal.h -v gMtl4SignalKernelLib

c++ -c -o build/gpu.o -fvisibility-inlines-hidden -fvisibility=hidden -fno-objc-arc -Wall -Wextra -Wpedantic -Iinclude -Isrc -std=c++11 -g -xobjective-c++ -fno-exceptions -fno-rtti -fno-unwind-tables -fno-asynchronous-unwind-tables -nostdlib++ src/_build/build.cpp
ar rcs build/libgpu.a build/gpu.o

