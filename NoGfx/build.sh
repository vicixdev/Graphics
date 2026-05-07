#!/usr/bin/env sh

set -e

c++ -c -o build/gpu.o -fvisibility-inlines-hidden -fvisibility=hidden -fno-objc-arc -Wall -Wextra -Wpedantic -Iinclude -Isrc -std=c++11 -g -xobjective-c++ -fno-exceptions -fno-rtti -fno-unwind-tables -fno-asynchronous-unwind-tables -nostdlib++ src/_build/build.cpp

ar rcs build/libgpu.a build/gpu.o

