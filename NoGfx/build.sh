#!/usr/bin/env sh

set -e

xcrun -sdk macosx metal -frecord-sources -gline-tables-only -c ./src/lib/metal4/shader/prep_multidrawindirect.metal -o ./build/prep_multidrawindirect.air
xcrun -sdk macosx metallib ./build/prep_multidrawindirect.air -o ./build/prep_multidrawindirect.metallib
./tools/bin2cpp.py ./build/prep_multidrawindirect.metallib -o ./src/lib/metal4/shader/prep_multidrawindirect.metal.cpp -H ./src/lib/metal4/shader/prep_multidrawindirect.metal.h -v gMtl4PrepareMultidrawIndirectIcbsBytecode

xcrun -sdk macosx metal -frecord-sources -gline-tables-only -c ./src/lib/metal4/shader/acquire_icb_range.metal -o ./build/acquire_icb_range.air
xcrun -sdk macosx metallib ./build/acquire_icb_range.air -o ./build/acquire_icb_range.metallib
./tools/bin2cpp.py ./build/acquire_icb_range.metallib -o ./src/lib/metal4/shader/acquire_icb_range.metal.cpp -H ./src/lib/metal4/shader/acquire_icb_range.metal.h -v gMtl4AcquireIcbRangeBytecode

c++ -c -o build/gpu.o -fvisibility-inlines-hidden -fvisibility=hidden -fno-objc-arc -Wall -Wextra -Wpedantic -Iinclude -Isrc -std=c++11 -g -xobjective-c++ -fno-exceptions -fno-rtti -fno-unwind-tables -fno-asynchronous-unwind-tables -nostdlib++ src/_build/build.cpp

ar rcs build/libgpu.a build/gpu.o

