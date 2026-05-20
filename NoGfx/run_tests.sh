#!/usr/bin/env sh

set -e

./build.sh
xcrun -sdk macosx metal -c ./test/shaders/compute.metal -o ./build/compute.air
xcrun -sdk macosx metallib ./build/compute.air -o ./build/compute.metallib
xcrun -sdk macosx metal -c ./test/shaders/compute_constants.metal -o ./build/compute_constants.air
xcrun -sdk macosx metallib ./build/compute_constants.air -o ./build/compute_constants.metallib
xcrun -sdk macosx metal -c ./test/shaders/render_vertex.metal -o ./build/render_vertex.air
xcrun -sdk macosx metallib ./build/render_vertex.air -o ./build/render_vertex.metallib
xcrun -sdk macosx metal -c ./test/shaders/render_vertex_constants.metal -o ./build/render_vertex_constants.air
xcrun -sdk macosx metallib ./build/render_vertex_constants.air -o ./build/render_vertex_constants.metallib
xcrun -sdk macosx metal -c ./test/shaders/render_fragment.metal -o ./build/render_fragment.air
xcrun -sdk macosx metallib ./build/render_fragment.air -o ./build/render_fragment.metallib
xcrun -sdk macosx metal -c ./test/shaders/render_fragment_constants.metal -o ./build/render_fragment_constants.air
xcrun -sdk macosx metallib ./build/render_fragment_constants.air -o ./build/render_fragment_constants.metallib
xcrun -sdk macosx metal -c ./test/shaders/meshlet.metal -o ./build/meshlet.air
xcrun -sdk macosx metallib ./build/meshlet.air -o ./build/meshlet.metallib
xcrun -sdk macosx metal -c ./test/shaders/meshlet_constants.metal -o ./build/meshlet_constants.air
xcrun -sdk macosx metallib ./build/meshlet_constants.air -o ./build/meshlet_constants.metallib
c++ -o ./build/test -g -Wall -Wextra -Wpedantic -Isrc -Iinclude -Lbuild -lgpu -framework Foundation -framework Metal -framework QuartzCore -std=c++11 ./test/main.cpp

./build/test

